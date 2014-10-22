package Gitpan::Repo;

# Handles the coordination of the Git and Gitpan repositories

use Gitpan::perl5i;

use Gitpan::OO;
use Gitpan::Types;

with 'Gitpan::Role::HasConfig';

haz distname =>
  is            => 'ro',
  isa           => DistName,
  required      => 1;

with 'Gitpan::Role::CanDistLog';

haz repo_dir =>
  isa           => Path,
  lazy          => 1,
  default       => method {
      $self->config->gitpan_repo_dir->child($self->distname_path);
  };

haz github =>
  is            => 'ro',
  isa           => InstanceOf['Gitpan::Github'],
  lazy          => 1,
  predicate     => 'has_github',
  clearer       => 'clear_github',
  default       => method {
      require Gitpan::Github;
      return Gitpan::Github->new(
          repo => $self->distname
      );
  };


haz git =>
  is            => 'ro',
  isa           => InstanceOf["Gitpan::Git"],
  lazy          => 1,
  predicate     => 'has_git',
  clearer       => 'clear_git',
  default       => method {
      my $github = $self->github;
      $github->maybe_create;

      require Gitpan::Git;
      return Gitpan::Git->new_or_clone(
          repo_dir => $self->repo_dir,
          url      => $github->remote,
          distname => $self->distname,
      );
  };
