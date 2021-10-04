#!/usr/bin/perl

## Written by Raymond A. Mouton 2021
## GitHub: https://github.com/ramouton/nut-batt_state

use strict;
use warnings;

use POSIX;

use Cwd 'abs_path';
use feature qw(switch say);
use List::Util 'first';

my @valid_line_states = ('charging','discharging','unknown');
my @valid_batt_states = ('ok','warn','low','crit');

my @valid_upssched_signals = ('onbatt','online','replacebatt','commbad','commok','powerdown');

my $cwd = getcwd; 

my $pid_file = "$cwd/.batt_pid";
my $state_file = "$cwd/.batt_state";

my $cat = '';
my $rm = '';
my $grep = '';
my $echo = '';
my $awk = '';
my $head = '';
my $date = '';
my $shutdown = '';
my $logger = '';
my $upsc = '';
my $qm_list = '';
my $qm_suspend = '';
my $qm_resume = '';

my $batt_mon = '';

my %battery_state_levels;

my $current_battery_charge = 0;
my $current_input_voltage = 0;

my $current_battery_state = '';
my $current_line_state = '';

my $lost_comm_at = '';
my $last_known_battery_charge = 0;


&main();
sub main() {
  my $incoming_upssched_signal = shift @ARGV;
  chomp($incoming_upssched_signal);


  if (grep $_ eq $incoming_upssched_signal, @valid_upssched_signals) {
    &init_commands();
    &write_state_file($incoming_upssched_signal);
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
    }
  } else {
    &usage();
  }
  
  exit(0);
}


sub battery_monitor() {

}

sub write_state_file($) {
  my $state_mesg = shift;
  my $state_changed = `$date +%s`;
  chomp($state_changed);
  if($state_mesg eq 'commbad') {
    $lost_comm_at = $state_changed;
    $last_known_battery_charge = $current_battery_charge;
    $current_line_state = 'unknown';
    $current_battery_charge = 'unknown';
  } else {
    $lost_comm_at = '';
    $last_known_battery_charge = 0;
    &get_battery_line_status();
  }
  unless (length($state_mesg) eq 0) {
    $state_mesg = $current_battery_state;
  }
  open STATEFILE, ">$state_file" or die "Couldn't open state file: $state_file: $!\n";
  print STATEFILE "$state_changed:$state_mesg:$current_line_state:$current_battery_charge\n";
  close STATEFILE;
  &log_ups_state($state_mesg);
}


sub read_state_file() {
  my $line_count = 0;
  my $max_line_count = 1;
  my $raw_state_message = '';
  open STATEFILE, "<$state_file" or die "Couldn't open state file: $state_file: $!\n";
  while(<STATEFILE>) {
    my $line = '';
    chomp($line=$_);
    if ($line_count lt $max_line_count) {
      $raw_state_message = $line;
    }
    $line_count++;
  }
  close STATEFILE;
  my @state = split(':',$raw_state_message);
  return @state;
}


sub log_ups_state($) {
  my $state_mesg = shift;
  my @ignore_state_messages = ('commbad','replacebatt');

  given($state_mesg) {
    when('replacebatt') {
      system("$logger \"The UPS needs a Battery Replacement.\"");
    }
    when('commbad') {
      system("$logger \"Lost communication with the UPS.\"");
    }
    when('commok') {
      system("$logger \"Communication restored with the UPS.\"");
    }
    when('powerdown') {
      system("$logger \"The UPS is critically low on battery, powering off the system\"");
    }
  }

  unless(grep $_ eq $state_mesg, @ignore_state_messages) {
    my $line_state_mesg = '';
    given($current_line_state) {
      when('charging') {
        $line_state_mesg = "The UPS is on line power and is Charging.";
      }
      when('discharging') {
        $line_state_mesg = "The UPS is on battery power and is Disharging.";
      }
    }
    my $battery_state_message = "The Battery charge is currently $current_battery_state. Charge: $current_battery_charge%";
    system("$logger \"$line_state_mesg $battery_state_message\"");
  }
  return;
}


sub get_battery_line_status() {

  my $raw_status = `$upsc $batt_mon`;
  chomp($raw_status);
  my @raw_status_array = split('\n', $raw_status);

  if(scalar(keys %battery_state_levels) eq 0) {
    my @matches = grep {/battery\.charge\./} @raw_status_array;
    for (my $idx = 0; $idx < scalar(@matches); $idx++) {
      my @var_array = split(': ', $matches[$idx]);
      if ($var_array[0] =~ /low/) {
        $battery_state_levels{'low'} = $var_array[1];
      } elsif ($var_array[0] =~ /warn/) {
        $battery_state_levels{'warn'} = $var_array[1];
      } elsif ($var_array[0] =~ /critical/) {
        $battery_state_levels{'crit'} = $var_array[1];
      } 
    }
    $battery_state_levels{'ok'} = 100;
  }
  my $raw_battery_charge = first {/battery.charge:/} @raw_status_array;
  my $raw_input_voltage = first {/input.voltage:/} @raw_status_array;
  my @raw_bc_array = split(': ', $raw_battery_charge);
  my @raw_iv_array = split(': ', $raw_input_voltage);

  $current_battery_charge = $raw_bc_array[1];
  $current_input_voltage = $raw_iv_array[1];

  if ($current_input_voltage gt 1) {
    $current_line_state = 'charging';
  } else {
    $current_line_state = 'discharging';
  }

  $current_battery_state = '';
  foreach my $key (reverse @valid_batt_states) {
    if (exists $battery_state_levels{$key}) {
      if ($current_battery_charge <= $battery_state_levels{$key}) {
        if ($current_battery_state eq '') {
          $current_battery_state = $key;
        } else {
          break;
        }
      }
    }
  }

  return;
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
  $shutdown = `which shutdown`;
  $logger = `which logger`;
  chomp($cat);
  chomp($rm);
  chomp($grep);
  chomp($echo);
  chomp($awk);
  chomp($head);
  chomp($date);
  chomp($shutdown);
  chomp($logger);
  $logger = "$logger -t ups_state";

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
