#!/usr/bin/env perl

use lib 't/lib';
use Gitpan::perl5i;
use Gitpan::Test;

my $CLASS = 'Gitpan::Config';
require_ok $CLASS;

subtest "github defaults" => sub {
    local $ENV{GITPAN_GITHUB_ACCESS_TOKEN};

    my $config = new_ok $CLASS;

    isa_ok $config->backpan_url, "URI";

    is $config->github_owner,           'gitpan';
    is $config->github_access_token,    'f58a7dfa0f749ccb521c8da38f9649e2eff2434f';
    is $config->github_remote_host,     'github.com';

    is $config->committer_name,         'Gitpan';
    is $config->committer_email,        'schwern+gitpan@pobox.com';

    is $config->gitpan_dir,             "$ENV{HOME}/gitpan";
    is $config->gitpan_log_dir,         "$ENV{HOME}/gitpan/log";
    is $config->gitpan_repo_dir,        "$ENV{HOME}/gitpan/repo";
};


subtest "github_access_token env" => sub {
    local $ENV{GITPAN_GITHUB_ACCESS_TOKEN} = 'deadbeef';

    my $config = new_ok $CLASS;

    is $config->github_access_token,    'deadbeef';
};

done_testing;
