#!/usr/bin/perl

## Written by Raymond A. Mouton 2021
## GitHub: https://github.com/ramouton/nut-batt_state

use strict;
use warnings;

use POSIX;

use Cwd 'abs_path';
use feature qw(switch say);

my @valid_line_states = ('charging','discharging');
my @valid_batt_states = ('ok','warn','low','crit');

my @valid_upssched_signals = ('onbatt','online','replacebatt','commbad','commok','powerdown');

my $cwd = abs_path($0);

my $pid_file = "$cwd/.batt_pid";
my $state_file = "$cwd/.batt_state";

my $cat = '';
my $rm = '';
my $grep = '';
my $echo = '';
my $awk = '';
my $head = '';
my $date = '';
my $logger = '';
my $upsc = '';
my $qm_list = '';
my $qm_suspend = '';
my $qm_resume = '';

my $batt_mon = '';

&main();
sub main() {
  my $incoming_upssched_signal = shift @ARGV;
  chomp($incoming_upssched_signal);

  if (grep $_ eq $incoming_upssched_signal, @valid_upssched_signals) {
    &init_commands();
    if ($incoming_upssched_signal eq 'onbatt') {
      unless((-f $pid_file) and (-s $pid_file)) {
        my $child_process;
         die "Can't fork: $!" unless defined ($child_process = fork());
         if ($child_process == 0) {
           &battery_monitor();
         } else {
           system("$echo $child_process > $pid_file");
           exit(0);
         }
      }
    } elsif ($incoming_upssched_signal eq 'replacebatt') {
      system("$logger \"The UPS Battery needs to be Replaced.\";");
      exit(0);
    }
  } else {
    &usage();
  }
  
  exit(0);
}


sub battery_monitor() {

}


sub init_commands() {
  my $qm = `which qm`;
  chomp($qm);
  if ($qm eq '') {
    print "\nUnable to continue, missing command: qm\nPlease run on a proxmox host\n\n";
    exit(1);
  }

  $cat = `which cat`;
  $rm = `which rm`;
  $grep = `which grep`;
  $echo = `which echo`;
  $awk = `which awk`;
  $head = `which head`;
  $date = `which date`;
  $logger = `which logger`;
  chomp($cat);
  chomp($rm);
  chomp($grep);
  chomp($echo);
  chomp($awk);
  chomp($head);
  chomp($date);
  chomp($logger);

  $upsc = `which upsc`;
  chomp($upsc);
  if ($upsc eq '') {
    print "\nUnable to continue, missing command: upsc\nPlease install nut-client\n\n";
    exit(1);
  }

  $qm_list = "$qm list";
  $qm_suspend = "$qm suspend";
  $qm_resume = "$qm resume";

  $batt_mon = `$cat $cwd/upsmon.conf|$grep MONITOR|$awk '{print \$2}'|$head -n 1`; 
}

sub usage() {

  print "./batt_state.pl SIGNAL\n";
  print "\twhere SIGNAL is one of: 'onbatt','online','replacebatt','commbad','commok','powerdown'\n\n";

  exit(0);
}
