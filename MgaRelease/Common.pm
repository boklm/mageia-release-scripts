package MgaRelease::Common;

use FindBin;
use YAML qw/LoadFile DumpFile/;
use URPM;
use SVN::Core;
use SVN::Ra;

my $c;
my $srpms_list;

sub config {
    $c ? $c : $c = LoadFile($FindBin::Bin. '/config');
}

sub config_path {
    my $file = config()->{$_[0]};
    $file =~ m|^/| ? $file : config()->{datadir} . '/' . $file;
}

sub make_srpms_list_from_synthesis {
    my $urpm = URPM->new;
    $srpms_list = {};
    foreach my $srpms_synthesis (@{config()->{srpms_synthesis}}) {
        $urpm->parse_synthesis($srpms_synthesis) 
            or die "Error reading $srpms_synthesis\n";
    }
    $urpm->traverse(sub { 
            $srpms_list->{$_[0]->name}->{version} = $_[0]->version;
            $srpms_list->{$_[0]->name}->{release} = $_[0]->release;
        });
}

sub save_srpms_list {
    DumpFile(config_path('srpms_list_file'), $srpms_list);
}

sub load_srpms_list {
    $srpms_list = LoadFile(config_path('srpms_list_file'), $srpms_list);
}

sub path_rev
{
    my ($ra, $path) = @_;
    if ($ra->check_path($path, $SVN::Core::INVALID_REVNUM)
        == $SVN::Node::none) {
        return undef;
    } else {
        return ($ra->get_dir($path,
                $SVN::Core::INVALID_REVNUM))[2]{'svn:entry:committed-rev'};
    }
}

sub get_srpms_rev {
    my $ra = SVN::Ra->new(config()->{svn_repourl});
    foreach my $pkg (keys %$srpms_list) {
        my ($ver, $rel) = @{$srpms_list->{$pkg}}{qw/version release/};
        $svnrev = path_rev($ra, "cauldron/$pkg/releases/$ver/$rel");
        $srpms_list->{$pkg}->{svnrev} = $svnrev if $svnrev;
    }
}

sub get_svn_branch_cmds {
    my $ci_msg = config()->{svn_branch_commit_msg};
    my $repo_url = config()->{svn_repourl};
    my $branch_path = config()->{svn_branch_path};
    open(my $branch, '>', config_path('branch_cmds_file')) 
        or die "Error opening " . config_path('branch_cmds_file') . "\n";
    open(my $nobranch, '>', config_path('nobranch_file'))
        or die "Error opening " . config_path('nobranch_file') . "\n";
    print $branch "#!/bin/sh\n";
    foreach my $pkg (keys %$srpms_list) {
        if ($srpms_list->{$pkg}->{svnrev}) {
            print $branch "svn cp -m '$ci_msg' $repo_url/cauldron/$pkg\@$srpms_list->{$pkg}->{svnrev} $repo_url/$branch_path/$pkg\n";
        } else {
            print $nobranch "$pkg\n";
        }
    }
}

sub get_current_diff {
    my $ra = SVN::Ra->new(config()->{svn_repourl});
    my $ctx = SVN::Client->new();
    my $diffdir = config_path('diffdir');
    my $repo_url = config()->{svn_repourl};
    foreach my $pkg (keys %$srpms_list) {
        next unless $srpms_list->{$pkg}->{svnrev}
                && $srpms_list->{$pkg}->{svnrev} != path_rev($ra, "cauldron/$pkg");

        my $difffile = config_path('diffdir') . '/' . $pkg;
        open(my $diffout, '>', $difffile) or die "Error opening file $difffile\n";
        $ctx->diff([], "$repo_url/cauldron/$pkg/current", $srpms_list->{$pkg}->{svnrev},
            "$repo_url/cauldron/$pkg/current", 'HEAD', 1, 0, 0,
            $diffout, $diffout);
        close $diffout;
    }
}

1;
