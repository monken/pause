#!/usr/local/bin/perl -w

use CPAN::Checksums 1.018;
use File::Copy qw(cp);
use File::Find;
use File::Spec;
use Time::HiRes qw(time);
use strict;

use lib "/home/k/PAUSE/lib";
use PAUSE ();

use Getopt::Long;
our %Opt;
GetOptions(\%Opt,
           "max=i",
           "debug!",
          ) or die;
$Opt{debug} ||= 0;
if ($Opt{debug}) {
  warn "Debugging on. CPAN::Checksums::VERSION[$CPAN::Checksums::VERSION]";
}
my $root = $PAUSE::Config->{MLROOT};
our $TESTDIR;

# max: 15 was really slow, 100 is fine, 1000 was temporarily used
# because of key-expiration on 2005-02-02; 1000 also seems appropriate
# now that we know that the process is not faster when we write less
# (2005-11-11); but lower than 1000 helps to smoothen out peaks
$Opt{max} ||= 64;

my $cnt = 0;

$CPAN::Checksums::CAUTION = 1;
$CPAN::Checksums::SIGNING_PROGRAM =
    $PAUSE::Config->{CHECKSUMS_SIGNING_PROGRAM};
$CPAN::Checksums::SIGNING_KEY =
    $PAUSE::Config->{CHECKSUMS_SIGNING_KEY};
$CPAN::Checksums::MIN_MTIME_CHECKSUMS =
    $PAUSE::Config->{MIN_MTIME_CHECKSUMS} || 0;

find(sub {
       exit if $cnt>=$Opt{max};
       return unless $File::Find::name =~ m|id/.|;
       return if -l;
       return unless -d;
       local($_); # Ouch, has it bitten that the following function
                  # did something with $_. Must have been a bug in 5.00556???

       # we need a way to force updatedir to run an update. If the
       # signature needs to be replaced for some reason. I do not know
       # which reason this will be, but it may happen. Something like
       # $CPAN::Checksums::FORCE_UPDATE?

       my $debugdir;
       my $start;
       if ( $Opt{debug} ) {
         require File::Temp;
         require File::Path;
         require File::Spec;
         $TESTDIR ||= File::Temp::tempdir(
                                          "update-checksums-XXXX",
                                          DIR => "/tmp",
                                          CLEANUP => 0,
                                         ) or die "Could not make a tmp directory";
         $debugdir = File::Spec->catdir($TESTDIR,
                                        substr($File::Find::name,
                                               length($root)));
         File::Path::mkpath($debugdir);
         cp(File::Spec->catfile(
                                $File::Find::name,
                                "CHECKSUMS"
                               ),
            File::Spec->catfile($debugdir,
                                "CHECKSUMS.old")
           ) or die $!;
         $start = time;
       }
       my $ffname = $File::Find::name;
       my $ret = eval { CPAN::Checksums::updatedir($ffname); };
       if ($@) {
         warn "error[$@] in checksums file[$ffname]: must unlink";
         unlink "$ffname/CHECKSUMS";
       }
       if ($Opt{debug}) {
         cp(File::Spec->catfile(
                                $ffname,
                                "CHECKSUMS"
                               ),
            File::Spec->catfile($debugdir,
                                "CHECKSUMS.new")
           ) or die $!;
         my $tooktime = sprintf "%.6f", time - $start;
         warn "debugdir[$debugdir]ret[$ret]tooktime[$tooktime]cnt[$cnt]\n"
       }
       return if $ret == 1;
       my $abs = File::Spec->rel2abs($ffname);
       PAUSE::newfile_hook("$abs/CHECKSUMS");
       $cnt++;
     }, $root);

