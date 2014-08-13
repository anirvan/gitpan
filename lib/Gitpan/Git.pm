package Gitpan::Git;

use Gitpan::perl5i;

use Gitpan::OO;
use Gitpan::Types;
use Git::Repository qw(Log);
with "Gitpan::Role::CanBackoff",
     "Gitpan::Role::HasConfig";

haz distname =>
  is            => 'ro',
  isa           => DistName;

with "Gitpan::Role::CanDistLog";

haz repo_dir =>
  is            => 'ro',
  isa           => AbsPath,
  lazy          => 1,
  default       => method {
      require Path::Tiny;
      return Path::Tiny->tempdir;
  };

haz git =>
  isa           => InstanceOf["Git::Repository"],
  handles       => [qw(
      run
      log
      git_dir
  )],
  lazy          => 1,
  default       => method {
      my $config = $self->config;

      return Git::Repository->new(
          work_tree => $self->repo_dir.'',
          {
              env => {
                  GIT_COMMITTER_EMAIL => $config->committer_email,
                  GIT_COMMITTER_NAME  => $config->committer_name,
                  GIT_AUTHOR_EMAIL    => $config->committer_email,
                  GIT_AUTHOR_NAME     => $config->committer_name,
              }
          },
      );
  };

method init($class: %args) {
    my $self = $class->new(%args);

    Git::Repository->run( init => $self->repo_dir );

    return $self;
}

# $url should be a URI|Path but Method::Signatures does not understand
# Type::Tiny (yet)
method clone(
    $class:
    Str :$url!,
    ArrayRef :$options = [],
    Str :$distname!,
    Path::Tiny :$repo_dir = Path::Tiny->tempdir
) {
    my $self = $class->new(
        distname        => $distname,
        $repo_dir ? (repo_dir        => $repo_dir) : ()
    );

    Git::Repository->run(
        clone => $url,
        $self->repo_dir,
        @$options,
        { quiet => 1 }
    );

    return $self;
}


method delete_repo {
    $self->repo_dir->remove_tree({ safe => 0 });
}


method clean {
    $self->remove_sample_hooks;
    $self->garbage_collect;
}

method hooks_dir {
    return $self->git_dir->path->child("hooks");
}

method garbage_collect {
    $self->run("gc");
}

# These sample hook files take up a surprising amount of space
# over thousands of repos.
method remove_sample_hooks {
    my $hooks_dir = $self->hooks_dir;
    return unless -d $hooks_dir;

    for my $sample ([$hooks_dir->children]->grep(qr{\.sample$})) {
        $sample->remove or warn "Couldn't remove $sample";
    }

    return 1;
}

method remotes() {
    my @remotes = $self->run("remote", "-v");
    my %remotes;
    for my $remote (@remotes) {
        my($name, $url, $action) = $remote =~ m{^ (\S+) \s+ (.*?) \s+ \( (.*?) \) $}x;
        $remotes{$name}{$action} = $url;
    }

    return \%remotes;
}

method remote( Str $name, Str $action = "push" ) {
    return $self->remotes->{$name}{$action};
}

method change_remote( Str $name, Str $url ) {
    my $remotes = $self->remotes;

    if( $remotes->{$name} ) {
        $self->set_remote_url( $name, $url );
    }
    else {
        $self->add_remote( $name, $url );
    }
}

method set_remote_url( Str $name, Str $url ) {
    $self->run( remote => "set-url" => $name => $url );
}

method add_remote( Str $name, Str $url ) {
    $self->run( remote => add => $name => $url );
}

method default_success_check($return?) {
    return $return ? 1 : 0;
}

method push( Str $remote //= "origin", Str $branch //= "master" ) {
    # sometimes github doesn't have the repo ready immediately after create_repo
    # returns, so if push fails try it again.
    my $ok = $self->do_with_backoff(
        times => 3,
        code  => sub {
            eval { $self->run(push => $remote => $branch, { quiet => 1 }); 1 };
        },
    );
    die "Could not push: $@" unless $ok;

    $self->run( push => $remote => $branch => "--tags", { quiet => 1 } );

    return 1;
}

method pull( Str $remote //= "origin", Str $branch //= "master" ) {
    my $ok = $self->do_with_backoff(
        times => 3,
        code  => sub {
            eval { $self->run(pull => $remote => $branch, { quiet => 1 }) } || return
        },
    );
    return $ok;
}

method rm_all {
    $self->run( rm => "--ignore-unmatch", "-fr", "." );
    # Clean up empty directories.
    $self->remove_working_copy;

    return;
}

method add_all {
    $self->run( add => "." );

    return;
}

method remove_working_copy {
    for my $child ( $self->repo_dir->children ) {
        next if $child->is_dir and $child->basename eq '.git';
        $child->is_dir ? $child->remove_tree : $child->remove;
    }
}

method revision_exists(Str $revision) {
    my $rev = eval { $self->run("rev-parse", $revision) } || return 0;
    return 1;
}

method releases {
    return [] unless $self->revision_exists("HEAD");

    my $tag_prefix = $self->config->cpan_release_tag_prefix;
    return [map { s{^$tag_prefix}{}; $_ } $self->run(tag => '-l', "$tag_prefix*")];
}

method commit_release(Gitpan::Release $release) {
    my $author = $release->author;

    my $commit_message = <<"MESSAGE";
Import of @{[ $author->pauseid ]}/@{[ $release->distvname ]} from CPAN.

gitpan-cpan-distribution: @{[ $release->distname ]}
gitpan-cpan-version:      @{[ $release->version ]}
gitpan-cpan-path:         @{[ $release->short_path ]}
gitpan-cpan-author:       @{[ $author->pauseid ]}
gitpan-cpan-maturity:     @{[ $release->maturity ]}

MESSAGE

    $self->run(
        "commit", "-m" => $commit_message,
        {
            env => {
                GIT_AUTHOR_DATE         => $release->date,
                GIT_AUTHOR_NAME         => $author->name,
                GIT_AUTHOR_EMAIL        => $author->email,
            },
        },
    );

    $self->tag_release($release);

    return;
}

# Some special handling when making versions tag safe.
method ref_safe_version(Str $version) {
    # Specifically change .1 into 0.1
    $version =~ s{^\.}{0.};

    return $version;
}

# See git-check-ref-format(1)
method make_ref_safe(Str $ref, :$substitution = "-") {
    # 6. They cannot begin or end with a slash / or contain multiple consecutive
    #    slashes.
    my @parts = grep { length } split m{/+}, $ref;

    for my $part (@parts) {
        # 1. no slash-separated component can begin with a dot .
        $part =~ s{^\.}{$substitution};

        # 1. or end with the sequence .lock
        $part =~ s{\.lock$}{$substitution};
    }

    $ref = join "/", @parts;

    # 3. They cannot have two consecutive dots
    $ref =~ s{\.{2,}}{\.}g;

    # 8. They cannot contain a sequence @{
    $ref =~ s{\@\{}{$substitution};

    # 4. They cannot have ASCII control characters (i.e. bytes whose values
    #    are lower than \040, or \177 DEL), space, tilde ~, caret ^, or
    #    colon : anywhere.
    # 5. They cannot have question-mark ?, asterisk *, or open bracket [ anywhere
    # 9. They cannot be the single character @
    # 10. They cannot contain a \
    $ref =~ s{[ [:cntrl:] [:space:] \~ \^ \: \? \* \[ \@ \\ ]+}{$substitution}gx;

    # 7. They cannot end with a dot
    $ref =~ s{\.$}{$substitution}g;

    return $ref;
}


method tag_release(Gitpan::Release $release) {
    # Tag the CPAN and Gitpan version
    my $safe_version = $self->ref_safe_version($release->version);

    $self->tag($self->config->cpan_release_tag_prefix.$safe_version);
    $self->tag($self->config->gitpan_release_tag_prefix.$safe_version);

    # Tag the CPAN Path
    $self->tag($self->config->cpan_path_tag_prefix.$release->short_path);

    # Update the latest stable/alpha release tag.
    $self->tag( $self->maturity2tag( $release->maturity ), force => 1 );

    # Update the latest release by this author.
    $self->tag( $release->author->pauseid,                 force => 1 );

    return;
}


# BackPAN::Index (via CPAN::DistnameInfo) has its own names for
# the maturity of a release which differ from CPAN conventions.
method maturity2tag( Str $maturity ) {
    state $maturity2tag = {
        released        => "stable",
        developer       => "alpha"
    };

    return $maturity2tag->{$maturity} || $maturity;
}


method tag(Str $name, Bool :$force = 0) {
    my @opts;
    @opts->push("-f") if $force;

    return $self->run("tag", @opts, $self->make_ref_safe($name));
}


method list_tags( ArrayRef :$patterns = [] ) {
    return $self->run("tag", "-l", @$patterns);
}
