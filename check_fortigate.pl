#!/usr/bin/perl -w
################################################################################
# Copyright (C) 2012 Olivier LI-KIANG-CHEONG
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
################################################################################
# Version : 1.0
################################################################################
# Author : Olivier LI-KIANG-CHEONG <lkco@gezen.fr>
################################################################################
# CHANGELOG :
# 1.0 : initial release
################################################################################

#global variables:
use strict;
use Net::SNMP;
use Data::Dumper;
use Bit::Vector;
use File::Basename;

use lib "/usr/lib/nagios/plugins";
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use vars qw($PROGNAME);
use Getopt::Long;
my ( $COMMUNITY, $HOST, $warning, $critical, $snmp_version, $error);
my ( $opt_h, $opt_H, $opt_C, $opt_v, $opt_v2, $opt_w, $opt_c, $opt_m, $opt_p);

$PROGNAME = basename($0);
sub print_help ();
sub print_usage ();
sub check_options ();
sub verb; 

########## OID ##########
my $fgVpnTunEntStatus      = ".1.3.6.1.4.1.12356.101.12.2.2.1.20";
my $fgVpnTunEntPhase1Name  = ".1.3.6.1.4.1.12356.101.12.2.2.1.2";
my $fgVpnTunEntInOctets    = ".1.3.6.1.4.1.12356.101.12.2.2.1.18";
my $fgVpnTunEntOutOctets   = ".1.3.6.1.4.1.12356.101.12.2.2.1.19";
my $fgHaSystemMode         = "1.3.6.1.4.1.12356.101.13.1.1.0"; # SYNTAX :INTEGER { standalone(1), activeActive(2), activePassive(3) }

# options definitions
Getopt::Long::Configure('bundling');
my $status_getop = GetOptions(
                        "h"    => \$opt_h,   "help"           => \$opt_h,
                        "H=s"  => \$opt_H,   "hostname=s"     => \$opt_H,
                        "C=s"  => \$opt_C,   "community=s"    => \$opt_C,
                        "v"    => \$opt_v,   "verbose"        => \$opt_v,
                        "2"    => \$opt_v2,  "v2c"            => \$opt_v2,
                        "w=s"  => \$opt_w,   "warning=s"      => \$opt_w,
                        "c=s"  => \$opt_c,   "critical=s"     => \$opt_c, 
                        "m:s"  => \$opt_m,   "mode:s"         => \$opt_m,
                        "p=s"  => \$opt_p,   "param:s"        => \$opt_p,
);

if ( $status_getop == 0 ) { 
    print_usage();
    exit $ERRORS{OK};
}

# the help :-)
sub print_usage () {
    print "Usage: $PROGNAME -H <host> -C SNMPv1community [-2] [-v] [-mode=ha|VPNTunnelList|VPNTunnel|VPNTunBandwidth] [-p param] [-w warning] [-c critical]\n";
}

sub print_help () {
    print "\n";
    print_usage();
    print "The script check the operationnal status of each FC port online of the switch.\n";
    print "With -T option, it can check temperature and bandwidth on FC port.\n\n";
    print "   -H (--hostname)                 Hostname to query - (required)\n";
    print "   -C (--community)                SNMP read community (defaults to public,\n";
    print "                                   used with SNMP v1 and v2c\n";
    print "   -v (--verbose)                  print extra verbging information\n";
    print "   -2 (--v2c)                      2 for SNMP v2c, by default\n";
    print "   -w (--warn)                     Signal strength at which a warning message will be generated\n";
    print "   -c (--crit)                     Signal strength at which a critical message will be generated\n";
    print "   -m,(--mode=) ha                 Check the HA, use -p to set the nominal mode \n";
    print "                                   mode : standalone, activeActive, activePassive\n";
    print "                VPNTunnelList      List VPNTunnel\n";
    print "                VPNTunnel          Check VPNTunnel status, use -p to set phase1 name \n";
    print "                VPNTunBandwidth    Check the bandwidth vnp, use -p to set phase1 name \n";
    print "                                   use -w and -c, warning and critical in o/s \n";
    print "   -p,(--param)                    Parameter for VPNTunnel or VPNTunBandwidth mode \n";
    print "   -h (--help)                     Usage help\n\n";
    print "Examples:\n";
    print "$PROGNAME -H <host> -C <SNMPv1community> --mode=ha";
    print "$PROGNAME -H <host> -C <SNMPv1community> --mode=VPNTunnelList";
    print "$PROGNAME -H <host> -C <SNMPv1community> --mode=VPNTunnel -p <phase1Name>";
    print "$PROGNAME -H <host> -C <SNMPv1community> --mode=VPNTunBandwidth -p <phase1Name> [-w <warn>] [-c <crit>]";

    support();
    exit $ERRORS{OK};
}

sub check_options () {
    verb("check options");
    # verification of parameters of the script
    print_help() if $opt_h; 
    unless ($opt_H) {
        print_usage();
        exit $ERRORS{CRITICAL};
    } 
    unless ($opt_C) {
        print_usage();
        exit $ERRORS{CRITICAL};
    }
    unless ($opt_m) {
        print_usage();
        exit $ERRORS{CRITICAL};
    }
    if ($opt_m) { 
        verb("check opt_m with $opt_m");
        if (($opt_m eq "VPNTunnel") and ( ! $opt_p )) { 
            verb("option -p missing");
            print "option -p missing for VPNTunnel mode\n";
            print_usage();
            exit $ERRORS{CRITICAL};
        } elsif (($opt_m eq "VPNTunBandwidth") and ( ! $opt_p ))  {
            verb("option -p missing");
            print "option -p missing for VPNTunBandwidth mode\n";
            print_usage();
            exit $ERRORS{CRITICAL};
        } elsif (($opt_m eq "ha") and ( ! $opt_p ))  {
            verb("option -p missing");
            print "option -p missing for ha mode, use [-p standalone|activeActive|activePassive]\n";
            print_usage();
            exit $ERRORS{CRITICAL};
        }
    }
}

sub verb { 
    my $text = shift; 
    print "== Debug == $text\n" if ($opt_v);
}

############  MAIN ############
check_options();
$COMMUNITY = $opt_C;
$HOST = $opt_H;
$warning = $opt_w;
$critical =$opt_c;
$snmp_version = "2";
$snmp_version = "2" if ($opt_v2);


verb("Try to connect Host => $HOST, Community => $COMMUNITY, Version => $snmp_version");
(my $session, $error) = Net::SNMP->session(-hostname => $HOST, 
                                           -community => $COMMUNITY, 
                                           -version => $snmp_version, 
                                           -port => 161);

if (!defined($session)) {
   print "ERROR opening session: $error \n";
   print "Unable to connect to $HOST ! Please verify the HOST or the community string : $COMMUNITY.\n";
   exit $ERRORS{"UNKNOWN"};
}
else {
    verb("Session OK");
}

# Run check
if ($opt_m eq "ha") {
    verb("Check HA mode");
    my $mode_nominal = $opt_p;
    verb("Search fgHaSystemMode");
        my $response = $session->get_request(-varbindlist => [$fgHaSystemMode]);
        if ( !defined($response )) {
            my $answer = $session->error;
            $session->close;
            print("WARNING: SNMP error: $answer\n");
            exit $ERRORS{'WARNING'};
        }

        verb($response->{$fgHaSystemMode});
        my $current_mode = $response->{$fgHaSystemMode};

        # SYNTAX :INTEGER { standalone(1), activeActive(2), activePassive(3) }
        my %h_HaMode = (
              "1" => "standalone",
              "2" => "activeActive",
              "3" => "activePassive",
        );
        if ( $h_HaMode{$current_mode} ne $mode_nominal ) {
            print "CRITICAL, HA mode is in ".$h_HaMode{$current_mode}." not $mode_nominal\n";
            exit $ERRORS{'CRITICAL'};
        } else{
            print "OK, HA mode is in ".$h_HaMode{$current_mode}."\n";
            exit $ERRORS{'OK'};
        } 
} elsif ($opt_m eq "VPNTunnelList" ) {
    verb("List VPNTunnel");
    my $response = $session->get_table("1.3.6.1.4.1.12356.101.12.2.2.1.2");
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
    print "List VPNTunnel:\n";
    foreach my $key ( sort keys %{$response} ) {
       verb("$key -> $response->{$key}");
       print "  $response->{$key}\n";
    }
    exit $ERRORS{'OK'};

} elsif ($opt_m eq "VPNTunnel" ) {
    verb("Check VPNTunnel status for $opt_p");
    my $VpnTunPhase1Name = $opt_p;
    my $response = $session->get_table("1.3.6.1.4.1.12356.101.12.2.2.1.2");
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
    my $tun_phase_index = "";
    foreach my $key ( sort keys %{$response} ) {
       verb("$key -> $response->{$key}");
       if ($response->{$key} eq "$VpnTunPhase1Name") {
           $key =~ /.*\.(\d+)$/;
           $tun_phase_index = $1;
           verb("Find it : index $tun_phase_index");
           last;
       }
    }

    if ($tun_phase_index eq "") {
        print "UNKNOWN : No Phase1Name found for $VpnTunPhase1Name\n";
        exit $ERRORS{'UNKNOWN'};;
    }

    verb("Search Status for $VpnTunPhase1Name : $fgVpnTunEntStatus.$tun_phase_index");
    $response = $session->get_table($fgVpnTunEntStatus);
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
    my $VpnTunEntStatus;
    foreach my $key ( sort keys %{$response} ) {
        if ( $key =~ m/$tun_phase_index$/) {
            verb("oid:$key value:$response->{$key}");
            $VpnTunEntStatus = $response->{$key};
            last;
        }
    }
    $session->close;

    verb("VpnTunEntStatus = '$VpnTunEntStatus'");
    # VpnTunEntStatus = 1, tunnel down
    # VpnTunEntStatus = 2, tunnel up
    if ($VpnTunEntStatus eq "1") {
        print "CRITICAL: VPN Tunnel $VpnTunPhase1Name is DOWN\n";
        exit $ERRORS{'CRITICAL'};
    } elsif ($VpnTunEntStatus eq "2") {
        print "OK: VPN Tunnel $VpnTunPhase1Name is UP\n";
        exit $ERRORS{'OK'};
    }
} elsif ($opt_m eq "VPNTunBandwidth" ) {
    $warning =  11250000; # 10,7 MB/s
    $critical = 12500000; # 11.9 MB/s
    $warning = $opt_w if ($opt_w);
    $critical =$opt_c if ($opt_c);
   
    verb("Check VPNTunnel bandwidth for $opt_p");
    my $cacheFile = "/tmp/traffic_cache_".$HOST."_".$opt_p;
    my $VpnTunPhase1Name = $opt_p;
    unless (-e $cacheFile) {
        # mustCreateFile
        my $response = $session->get_table("1.3.6.1.4.1.12356.101.12.2.2.1.2");
        if ( !defined($response )) {
            my $answer = $session->error;
            $session->close;
            print("WARNING: SNMP error: $answer\n");
            exit $ERRORS{'WARNING'};
        }
        my $tun_phase_index = "";
        foreach my $key ( sort keys %{$response} ) {
           verb("$key -> $response->{$key}");
           if ($response->{$key} eq "$VpnTunPhase1Name") {
               $key =~ /.*\.(\d+)$/;
               $tun_phase_index = $1;
               verb("Find it : index $tun_phase_index");
               last;
           }
        }

        if ($tun_phase_index eq "") {
            print "UNKNOWN : No Phase1Name found for $VpnTunPhase1Name\n";
            exit $ERRORS{'UNKNOWN'};;
        }

        verb("Search fgVpnTunEntInOctets for $VpnTunPhase1Name : $fgVpnTunEntInOctets.$tun_phase_index");
        verb("Search fgVpnTunEntOutOctets for $VpnTunPhase1Name : $fgVpnTunEntOutOctets.$tun_phase_index");
        my $OID_IN= "$fgVpnTunEntInOctets.$tun_phase_index";
        my $OID_OUT= "$fgVpnTunEntOutOctets.$tun_phase_index";
        my $current_time;
        my $current_InOctets;
        my $current_OutOctets;
        $response = $session->get_request(-varbindlist => [$OID_IN,$OID_OUT]);
        if ( !defined($response )) {
            my $answer = $session->error;
            $session->close;
            print("WARNING: SNMP error: $answer\n");
            exit $ERRORS{'WARNING'};
        }
        verb($response->{$OID_IN});
        verb($response->{$OID_OUT});
        $current_time = time();
        $current_InOctets = $response->{$OID_IN};
        $current_OutOctets = $response->{$OID_OUT};

        verb("Create $cacheFile");
        verb("Cache file must be created $cacheFile");
        print "UNKNOWN: Cache file must be created\n";
        open(FILE,">".$cacheFile);
        print FILE $current_time."\n";
        print FILE "$OID_IN;$current_InOctets\n";
        print FILE "$OID_OUT;$current_OutOctets\n";
        close(FILE);

        exit $ERRORS{'UNKNOWN'};
    }else{
        my $delta_time;
        my $OID_IN;
        my $OID_OUT;
        my $last_InOctets;
        my $last_OutOctets;
        my $current_time = time();
        my $current_InOctets;
        my $current_OutOctets;
        
        # Read cacheFile
        verb("Open $cacheFile");
        open(FILE,"<".$cacheFile);
        my @content = <FILE>;
        close(FILE);

        map(chomp,@content);
        $delta_time = $current_time - $content[0];
        verb("delta_time : $delta_time");
        ($OID_IN, $last_InOctets) = split(/;/,$content[1]);
        ($OID_OUT, $last_OutOctets) = split(/;/,$content[2]);
        verb("OID_IN: $OID_IN");
        verb("OID_OUT: $OID_OUT");
        chomp $last_InOctets;
        chomp $last_OutOctets;
        verb("last_InOctets: $last_InOctets");
        verb("last_OutOctets: $last_OutOctets");

        # Search OID
        verb("Search fgVpnTunEntInOctets fgVpnTunEntOutOctets");
        my $response = $session->get_request(-varbindlist => [$OID_IN,$OID_OUT]);
        if ( !defined($response )) {
            my $answer = $session->error;
            $session->close;
            print("WARNING: SNMP error: $answer\n");
            exit $ERRORS{'WARNING'};
        }
        verb("current_InOctets: ".$response->{$OID_IN});
        verb("current_OutOctets: ".$response->{$OID_OUT});
        $current_InOctets = $response->{$OID_IN};
        $current_OutOctets = $response->{$OID_OUT};

        # Save cache file 
        verb("Update cache file $cacheFile");
        open(FILE,">".$cacheFile);
        print FILE $current_time."\n";
        print FILE "$OID_IN;$current_InOctets\n";
        print FILE "$OID_OUT;$current_OutOctets\n";
        close(FILE);

        # Calculate bandwidth
        my $In_bandwidth;
        my $Out_bandwidth;
        $In_bandwidth  = sprintf("%.1f", ($current_InOctets - $last_InOctets) / $delta_time);
        $Out_bandwidth = sprintf("%.1f", ($current_OutOctets - $last_OutOctets) / $delta_time);
        verb("In_bandwidth : $In_bandwidth");
        verb("Out_bandwidth: $Out_bandwidth");
        my $message = "OK";
        my $exit_code = $ERRORS{'OK'};
        my $perfdata = "| traffic_in=".$In_bandwidth."o/s;;;0; traffic_out=".$Out_bandwidth."o/s ;;;0;";
        if (($In_bandwidth > $critical) || ($Out_bandwidth > $critical)) {
            $message = "CRITICAL";
            $exit_code = $ERRORS{'CRITICAL'};
        } elsif (($In_bandwidth > $warning) || ($Out_bandwidth > $warning)) {
            $message = "WARNING";
            $exit_code = $ERRORS{'WARNING'};
        }

        $message .= ", Traffic In : $In_bandwidth o/s, Out : $Out_bandwidth o/s $perfdata\n";
        print $message;
        exit $exit_code;
    }
}

