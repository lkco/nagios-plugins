#!/usr/bin/perl -w
################################################################################
# Copyright (C) 2010 Olivier LI-KIANG-CHEONG
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
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
use vars qw($opt_h $opt_H $opt_C $opt_v $opt_v2 $opt_w $opt_c $opt_T $opt_n);
my ( $HOST,   $COMMUNITY, $warning, $critical, $snmp_version );
my ( $NB_WARNING,   $MSG,  $type, $error );
my ( $ports_number, $port, $FC_oper_port, $FC_adm_status, $FC_phys_status );

$PROGNAME = basename($0);
sub print_help ();
sub print_usage ();
sub check_options ();
sub verb; 

my $REGEX_TEMP_STATUS = "Temperature Status";
my $REGEX_TEMP_SENSOR = "Temperature Sensor";
my $REGEX_POWER = "Power supply";

########## OID ##########
# FC Status
my $CiscoConnUnitPortState = "1.3.6.1.3.94.1.10.1.6";

# Sensors Status
my $CiscoconnUnitSensorName = "1.3.6.1.3.94.1.8.1.3"; 
my $CiscoConnUnitSensorStatus = "1.3.6.1.3.94.1.8.1.4";
my $CiscoConnUnitSensorMessage = "1.3.6.1.3.94.1.8.1.6";
# Temperature code
# 3 OK => Normal 
# 4 warning => warm 
# 5 failed  => Overheating 
# 1 unkwon => Other
# Powersupply code
# 3 OK => Good 
# 5 failed  => Bad
# 1 unkwon => Other

# Bandwidth
my $CiscoConnUnitPortSpeed = "1.3.6.1.3.94.1.10.1.15";
my $CiscoConnUnitPortStatCountTxObjects = "1.3.6.1.3.94.4.5.1.6"; # A hexidecimal value indicating the total number of bytes transmitted by a port 
my $CiscoConnUnitPortStatCountRxObjects = "1.3.6.1.3.94.4.5.1.7"; # A hexidecimal value indicating the total number of bytes received by a port 


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
                        "T=s"  => \$opt_T,
                        "n=s"  => \$opt_n
);

if ( $status_getop == 0 ) { 
    print_usage();
    exit $ERRORS{OK};
}

# the help :-)
sub print_usage () {
    print "Usage: $PROGNAME -H <host> -C SNMPv1community [-2] [-v] [-T=temperature|powersupply|(bandwidth -n <interface> -w <warning> -c <critical>)]\n";
}

sub print_help () {
    print "\n";
    print_usage();
    print "The script check the operationnal status of each FC port online of the switch.\n";
    print "With -T option, it can check temperature and bandwidth on FC port.\n\n";
    print "   -H (--hostname)   Hostname to query - (required)\n";
    print "   -C (--community)  SNMP read community (defaults to public,\n";
    print "                     used with SNMP v1 and v2c\n";
    print "   -v (--verbose)    print extra verbging information\n";
    print "   -2 (--v2c)        2 for SNMP v2c\n";
    print "   -w (--warn)       Signal strength at which a warning message will be generated\n";
    print "   -c (--crit)       Signal strength at which a critical message will be generated\n";
    print "   -T temperature    Check the switch temperature\n";
    print "   -T bandwidth      Check the bandwidth of FC port\n";
    print "   -T powersupply    Check the bandwidth of FC port\n";
    print "   -n                Interface number\n";
    print "   -h (--help)       usage help\n\n";

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
    if ($opt_T) { 
    verb("check opt_T");
        if (($opt_T eq "bandwidth") and ( ! $opt_w || ! $opt_c || ! $opt_n )) { 
verb("test1");
            print_usage();
            exit $ERRORS{CRITICAL};
        } elsif ($opt_T ne "temperature" && $opt_T ne "powersupply" && $opt_T ne "bandwidth") {
verb("test2");
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
$snmp_version = "1";
$snmp_version = "2" if ($opt_v2);


verb("Try to connect Host => $HOST, Community => $COMMUNITY, Version => $snmp_version");
(my $session, $error) = Net::SNMP->session(-hostname => $HOST, -community => $opt_C, -version => 1, -port => 161);

if (!defined($session)) {
   print "ERROR opening session: $error \n";
   print "Unable to connect to $HOST ! Please verify the HOST or the community string : $COMMUNITY.\n";
   exit $ERRORS{"UNKNOWN"};
}
else {
    verb("Session OK");
}

# Run check
unless ($opt_T) {
    # Verify that the FC port is active 
    # status results:
    # 1 unknown
    # 2 online
    # 3 offline
    # 5 diagnostics
 
    verb("Check FC Port");
    my $response = $session->get_table($CiscoConnUnitPortState);
    if ( !defined($response )) {
	my $answer = $session->error;
	$session->close;
	print("WARNING: SNMP error: $answer\n");
	exit $ERRORS{'WARNING'};
    }
    my @port_up;
    my @port_down; 
    my $size = 0;
    foreach my $key ( sort keys %{$response} ) {
        $size++;
        $key =~ /.*\.(\d+)$/;
	my $num_port = $1;
        my $state = $response->{$key};
        verb("port $num_port : state $state");
        if ($state =~ m/[2]/) {
            push( @port_up, $num_port);
        } elsif ($state =~ m/[15]/) {
            push( @port_down, $num_port);
        } 
    }

    @port_up = sort @port_up;
    @port_down = sort @port_down;
    my $nb_port_up = scalar(@port_up);
    my $nb_port_down = scalar(@port_down);
    my $exit_code = 0;
    my $msg = "";
    verb("nb_port_up=$nb_port_up, nb_port_down=$nb_port_down");
    if ($nb_port_down == "0") {
        $exit_code = $ERRORS{"OK"};
        $msg = $msg."All FC ports are OK. ";
        
    } else{
        $exit_code = $ERRORS{"CRITICAL"};
        $msg = $msg."FC port are faulty ! ";
        if ($nb_port_down > 0) {
            $msg = $msg."Port faulty : ". join(',',@port_down) . ". ";
        }
    }
    if ($nb_port_up > 0) {
        $msg = $msg."Port online : ". join(',',@port_up) . ". ";
    } elsif ($nb_port_up > 0) {
        $msg = $msg."All port are offline. ";
    } 
    verb("print perfadata");
    $msg = $msg."| num_port_online=$nb_port_up;;;0;$size num_port_faulty=$nb_port_down;;;0;$size";

    $session->close;
    print "$msg\n";
    exit $exit_code;

} elsif ($opt_T eq "temperature" ) {
    verb("Check Temperature");
    my $response = $session->get_table($CiscoconnUnitSensorName);
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
 
    my $temp_status_index;
    my $temp_status_name;
    my $temp_sensor_oid;
    my $temp_sensor_value;

    foreach my $key ( sort keys %{$response} ) {
        if ( $response->{$key} =~ /$REGEX_TEMP_STATUS/ ) {
            $key =~ /.*\.(\d+)$/;
            $temp_status_index = $1;
            $temp_status_name = $response->{$key};
        } elsif ( $response->{$key} =~ m/$REGEX_TEMP_SENSOR/ ) {
            $temp_sensor_oid = $key;
            $temp_sensor_oid =~ s/$CiscoconnUnitSensorName//;
            $temp_sensor_value = $response->{$key};
        }

    }

    verb("temp_status_index = '$temp_status_index'");
    verb("temp_status_name = '$temp_status_name'");
    verb("temp_sensor_oid = '$temp_sensor_oid'");
    verb("temp_sensor_value = '$temp_sensor_value'");

    verb("Search SensorStatus for $temp_status_index");
    $response = $session->get_table($CiscoConnUnitSensorStatus);
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
 
    my $sensor_status;
    foreach my $key ( sort keys %{$response} ) {
        if ( $key =~ m/$temp_status_index$/) {
            verb("oid:$key value:$response->{$key}");
            $sensor_status = $response->{$key};
	    last;
        }
    }

    verb("Search SensorMessage for $temp_status_index");
    $response = $session->get_request(-varbindlist => [$CiscoConnUnitSensorMessage.$temp_sensor_oid] );
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
 
    verb("SensorMessage for $temp_status_index : $response->{$CiscoConnUnitSensorMessage.$temp_sensor_oid}");
    my $temperature;
    if ($response->{$CiscoConnUnitSensorMessage.$temp_sensor_oid} =~ m/(\d+)/ ){
        $temperature = $1;
    }
  
# status_code :
# 3 OK => Normal 
# 4 warning => warm 
# 5 failed  => Overheating 
# 1 unknown => Other
    my $exit_code = 0;
    my $msg = "";
    if ($sensor_status == 3) {
        $exit_code = $ERRORS{'OK'};
        $msg = $msg. "Temperature Status is normal";
    } elsif ($sensor_status == 4) {
        $exit_code = $ERRORS{'WARNING'};
        $msg = $msg. "Temperature Status is warm";
    } elsif ($sensor_status == 5) {
        $exit_code = $ERRORS{'CRITICAL'};
        $msg = $msg. "Temperature Status is Overheating";
    } elsif ($sensor_status == 1) { 
        $exit_code = $ERRORS{'UNKNOWN'};
        $msg = $msg. "Temperature Status is unknown";
    }

    if (defined($temperature)) {
        verb("print perfdata");
        $msg = $msg. " | temp=".$temperature."C;;;0;";
    }
    $session->close;
    print "$msg\n";
    exit $exit_code;
} elsif ($opt_T eq "powersupply" ) {
    verb("Check Power supply $CiscoconnUnitSensorName");
    my $response = $session->get_table($CiscoconnUnitSensorName);
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
 
    my $power_status_index;
    my $power_status_name;
    foreach my $key ( sort keys %{$response} ) {
        verb("$response->{$key}");
        if ( $response->{$key} =~ m/$REGEX_POWER/ ) {
            $key =~ /.*\.(\d+)$/;
            $power_status_index = $1;
            $power_status_name = $response->{$key};
            last;
        } 
    }
    verb("power_status_index = '$power_status_index'");
    verb("power_status_name = '$power_status_name'");

    verb("Search SensorStatus for $power_status_index");
    $response = $session->get_table($CiscoConnUnitSensorStatus);
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
 
    my $sensor_status;
    foreach my $key ( sort keys %{$response} ) {
        if ( $key =~ m/$power_status_index$/) {
            verb("oid:$key value:$response->{$key}");
            $sensor_status = $response->{$key};
	    last;
        }
    }

    verb("Search SensorMessage for $power_status_index");
    $response = $session->get_table($CiscoConnUnitSensorMessage);
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
 
    my $power_sensor_message;
    foreach my $key ( sort keys %{$response} ) {
        if ( $key =~ m/$power_status_index$/) {
            verb("oid:$key value:$response->{$key}");
            $power_sensor_message = $response->{$key};
            last;
        } 
    }

 
    verb("SensorMessage for $power_status_index : $power_sensor_message");
  
# status_code :
# 3 OK => Normal 
# 5 failed  => Overheating 
# 1 unknown => Other
    my $exit_code = 0;
    my $msg = "";
    if ($sensor_status == 3) {
        $exit_code = $ERRORS{'OK'};
        $msg = $msg. "$power_status_name is $power_sensor_message";
    } elsif ($sensor_status == 5) {
        $exit_code = $ERRORS{'CRITICAL'};
        $msg = $msg. "$power_status_name is $power_sensor_message";
    } elsif ($sensor_status == 1) { 
        $exit_code = $ERRORS{'UNKNOWN'};
        $msg = $msg. "$power_status_name is $power_sensor_message";
    }

    $session->close;
    print "$msg\n";
    exit $exit_code;
} elsif ($opt_T eq "bandwidth") {
 
    my $interface = $opt_n; 

    my $msg = "";
    my $exit_code = 0;

    verb("Check Bandwidth");
    my $buffer_file = "/tmp/".$PROGNAME."_".$HOST."_".$interface;
    unless (-e $buffer_file) {
        verb("Create buffer file $buffer_file");
        my $response = $session->get_table($CiscoConnUnitPortStatCountTxObjects);
        if ( !defined($response )) {
            my $answer = $session->error;
            $session->close;
            print("WARNING: SNMP error: $answer\n");
            exit $ERRORS{'WARNING'};
        }
 
        my $TxObjects = "";
        my $TxObjectsOid = "";
        foreach my $key ( sort keys %{$response} ) {
            if ( $key =~ m/\.$interface$/) {
                verb("oid:$key value:$response->{$key}");
                $TxObjects = $response->{$key};
                $TxObjectsOid = $key;
	        last;
            }
        }

        $response = $session->get_table($CiscoConnUnitPortStatCountRxObjects);
        if ( !defined($response )) {
            my $answer = $session->error;
            $session->close;
            print("WARNING: SNMP error: $answer\n");
            exit $ERRORS{'WARNING'};
            exit $exit_code; 
        }
 
        my $RxObjects = "";
        my $RxObjectsOid = "";
        foreach my $key ( sort keys %{$response} ) {
            if ( $key =~ m/\.$interface$/) {
                verb("oid:$key value:$response->{$key}");
                $RxObjects = $response->{$key};
                $RxObjectsOid = $key;
	        last;
            }
        }


        if ( $TxObjectsOid ne "" && $RxObjectsOid ne "" && $TxObjects =~ m/0x[0-9A-Fa-f]+/ && $RxObjects =~ m/0x[0-9A-Fa-f]+/ ) {
            if (open(OUT,">".$buffer_file) ) {
                verb("HEX TxObjects='$TxObjects' RxObjects='$RxObjects'");
                #my $vec1, my $vec2;
                #$vec1 = Bit::Vector->new_Hex(64, $TxObjects);
                #$vec2 = Bit::Vector->new_Hex(64, $RxObjects);
                #$TxObjects = $vec1->to_Dec();
                #$RxObjects = $vec2->to_Dec();
                #verb("DEC TxObjects='$TxObjects' RxObjects='$RxObjects'");

                $msg .= "Creating Buffer";
                my $current_time = time();
                verb("Current $current_time:$TxObjects:$RxObjects");
                verb("Tx:".$TxObjectsOid.":".$TxObjects);
                verb("Rx:".$RxObjectsOid.":".$RxObjects);
                print OUT "$current_time\n";
                print OUT "Tx:".$TxObjectsOid.":".$TxObjects."\n";
                print OUT "Rx:".$RxObjectsOid.":".$RxObjects."\n";
                close(OUT);
            } else {
                print "UNKNOWN: Can't find snmp bandwidth information\n";
                $exit_code = $ERRORS{'UNKNOWN'};
                exit $exit_code; 
            }
        }
        $exit_code = $ERRORS{'UNKNOWN'};
    } else{
        ## Retrieve last information
        open(IN,$buffer_file);
        my @content = <IN>;
        close(IN);
        if (scalar(@content) == 0) { # no line found
            unlink ($buffer_file);
            $exit_code = $ERRORS{'UNKNOWN'};
            $msg .= "No Buffer found, it'll created for next check";
            
        } else{
            map(chomp,@content);
            my $last_time = $content[0];
            my $drop;
            ($drop,my $TxObjectsOid, my $last_TxObjects) = split(/:/, $content[1], 3);
            ($drop,my $RxObjectsOid, my $last_RxObjects) = split(/:/, $content[2], 3);

            if ( ! defined($last_time) && ! defined($TxObjectsOid) && ! defined($last_TxObjects) ) {
                unlink ($buffer_file);
                $msg .= "No Buffer found, it'll created for next check";
                $exit_code = $ERRORS{'UNKNOWN'};
                exit $exit_code; 
            }
            
            ## Retrieve current information
            verb("Retrieve current information");
            my $response = $session->get_request(-varbindlist => [$TxObjectsOid,$RxObjectsOid] );
            if ( !defined($response )) {
                my $answer = $session->error;
                $session->close;
                print("WARNING: SNMP error: $answer\n");
                exit $ERRORS{'WARNING'};
            }

            my $TxObjects = $response->{$TxObjectsOid};
            my $RxObjects = $response->{$RxObjectsOid};
            verb("HEX TxObjects='$TxObjects' RxObjects='$RxObjects'");

            my $V_TxObjects, my $V_RxObjects;
            my $V_last_TxObjects, my $V_last_RxObjects;
            $V_TxObjects = Bit::Vector->new_Hex(64, $TxObjects);
            $V_RxObjects = Bit::Vector->new_Hex(64, $RxObjects);
            $V_last_TxObjects = Bit::Vector->new_Hex(64, $last_TxObjects);
            $V_last_RxObjects = Bit::Vector->new_Hex(64, $last_RxObjects);
            #$TxObjects = $V_TxObjects->to_Dec();  
            #$RxObjects = $V_RxObjects->to_Dec();  
            #verb("DEC TxObjects='$TxObjects' RxObjects='$RxObjects'");

            my $current_time = time();
            verb("Last $last_time:$last_TxObjects:$last_RxObjects");
            verb("Current $current_time:$TxObjects:$RxObjects");
            if ($current_time <= $last_time ) {
                print("ERROR: Can't evaluate data\n");
                exit $ERRORS{'ERROR'};
            }

            if ( $TxObjectsOid ne "" && $RxObjectsOid ne "" && $TxObjects =~ m/0x[0-9A-Fa-f]+/ && $RxObjects =~ m/0x[0-9A-Fa-f]+/ ) {
                if (open(OUT,">".$buffer_file) ) {
                    verb("Tx:".$TxObjectsOid.":".$TxObjects);
                    verb("Rx:".$RxObjectsOid.":".$RxObjects);
                    print OUT $current_time."\n";
                    print OUT "Tx:".$TxObjectsOid.":".$TxObjects."\n";
                    print OUT "Rx:".$RxObjectsOid.":".$RxObjects."\n";
                    close(OUT);
                } 
            } else {
                print "UNKNOWN: Can't find snmp bandwidth information\n";
                $exit_code = $ERRORS{'UNKNOWN'};
                exit $exit_code; 
            }

            my $TXdiff = $V_TxObjects->to_Dec()-$V_last_TxObjects->to_Dec();
            my $RXdiff = $V_RxObjects->to_Dec()-$V_last_RxObjects->to_Dec();
            
            $TXdiff = 0 if ($TXdiff < 0);
            $RXdiff = 0 if ($RXdiff < 0);
            verb("TXdiff='$TXdiff' RXdiff='$RXdiff'");
            my $Txbandwidth =  sprintf("%.1f",($TXdiff)/($current_time-$last_time)); 
            my $Rxbandwidth =  sprintf("%.1f",($RXdiff)/($current_time-$last_time)); 

            verb("Txbandwidth = $Txbandwidth (o/s) | Rxbandwidth=$Rxbandwidth (o/s)");

            $response = $session->get_table($CiscoConnUnitPortSpeed);
            if ( !defined($response )) {
                my $answer = $session->error;
                $session->close;
                print("WARNING: SNMP error: $answer\n");
                exit $ERRORS{'WARNING'};
            }
 
	    my $PortSpeed; # The speed of the port in kilobytes per second. 
            foreach my $key ( sort keys %{$response} ) {
                if ( $key =~ m/\.$interface$/) {
                    verb("PortSpeed oid:$key value:$response->{$key}");
                    $PortSpeed = $response->{$key};
                    last;
                }
            }

            unless (defined($PortSpeed)) {
                print "UNKNOWN: Can't find snmp speed port $interface\n";
                exit $ERRORS{'WARNING'};
            }

            $PortSpeed *= 1024;
            my $TX_usage_percent = sprintf("%.f",($Txbandwidth * 100) / $PortSpeed);
            my $RX_usage_percent = sprintf("%.f",($Rxbandwidth * 100) / $PortSpeed);
            $TX_usage_percent = 100 if ($TX_usage_percent > 100) ;
            $RX_usage_percent = 100 if ($RX_usage_percent > 100) ;

            verb("TX_usage_percent:".$TX_usage_percent."% RX_usage_percent:".$RX_usage_percent."%");

            if (($TX_usage_percent > $critical) || ($RX_usage_percent > $critical)) {
                $exit_code = $ERRORS{'CRITICAL'};
            } elsif (($TX_usage_percent > $warning) || ($RX_usage_percent > $warning)) {
                $exit_code = $ERRORS{'WARNING'};
            }
            $msg .= "Traffic In : $Rxbandwidth o/s ($RX_usage_percent %), Out : $Txbandwidth o/s ($TX_usage_percent %)";
            $msg .= " | traffic_in=".$Rxbandwidth."o/s;;;0;".$PortSpeed." traffic_out=".$Txbandwidth."o/s;;;0;".$PortSpeed;
        }
    }
    $session->close;
    print "$msg\n";
    exit $exit_code;
}

