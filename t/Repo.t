#!/usr/bin/perl

use lib 't/lib';
use perl5i::2;
use Gitpan::Test;

use Gitpan::Repo;


note "repo data"; {
    my $repo = Gitpan::Repo->new( distname => "Foo-Bar" );
    isa_ok $repo, "Gitpan::Repo";

    is $repo->distname, "Foo-Bar";
    is $repo->directory, "Foo-Bar"->path->absolute;
}


note "Recover from a module name"; {
    my $repo = Gitpan::Repo->new( modulename => "This::That::Whatever" );
    is $repo->distname, "This-That-Whatever";
}


note "github"; {
    my $repo = Gitpan::Repo->new( distname => "Foo-Bar" );
    my $gh = $repo->github;
    isa_ok $gh, "Gitpan::Github";
    is $gh->owner, "gitpan-test";
    is $gh->repo,  "Foo-Bar";

    $repo->github({ login => "wibble", access_token => 12345 });
    $gh = $repo->github;
    isa_ok $gh, "Gitpan::Github";
    is $gh->login, "wibble";
    is $gh->access_token, 12345;
    is $gh->owner, "gitpan-test";
    is $gh->repo,  "Foo-Bar";

    my $repo2 = Gitpan::Repo->new(
        distname  => "Test-This",
        directory => "foo/bar",
        github    => {
            access_token => 54321,
            login        => 12345,
        }
    );
    isa_ok $repo2, "Gitpan::Repo";
    $gh = $repo2->github;
    isa_ok $gh, "Gitpan::Github";
    is $gh->login, "12345";
    is $gh->access_token, "54321";
    is $gh->owner, "gitpan-test";
    is $gh->repo,  "Test-This";
}


note "git"; {
    my $repo = Gitpan::Repo->new( distname => "Foo-Bar" );
    my $git = $repo->git;
    isa_ok $git, "Gitpan::Git";
    ok -d $repo->directory;
    END { $repo->directory->remove_tree }

    ok -d $repo->directory->child(".git");
}

done_testing;
