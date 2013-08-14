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
use File::Basename;

use lib "/usr/lib/nagios/plugins";
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use vars qw($PROGNAME);
use Getopt::Long;
use vars qw($opt_h $opt_H $opt_C $opt_v $opt_v2 $opt_w $opt_c $opt_d $opt_f);
my ( $HOST, $COMMUNITY, $warning, $critical, $snmp_version, $factor, $error );

$PROGNAME = basename($0);

########## Function declaration ##########
sub print_help ();
sub print_usage ();
sub check_options ();
sub verb; 

########## Variable Global ##########

########## OID ##########
my $dskIOTable    = "1.3.6.1.4.1.2021.13.15.1";
my $dskIOEntry    = "1.3.6.1.4.1.2021.13.15.1.1";
my $dskIOIndex    = "1.3.6.1.4.1.2021.13.15.1.1.1";
my $dskIODevice   = "1.3.6.1.4.1.2021.13.15.1.1.2";
my $dskIONRead    = "1.3.6.1.4.1.2021.13.15.1.1.3"; # The number of bytes read from this device since boot.
my $dskIONWritten = "1.3.6.1.4.1.2021.13.15.1.1.4"; # The number of bytes written to this device since boot.
my $dskIOReads    = "1.3.6.1.4.1.2021.13.15.1.1.5"; # The number of read accesses from this device since boot.
my $dskIOWrites   = "1.3.6.1.4.1.2021.13.15.1.1.6"; # The number of write accesses to this device since boot.

# options definitions
########## Options definitions ##########
Getopt::Long::Configure('bundling');
my $status_getop = GetOptions(
                        "h"    => \$opt_h,   "help"           => \$opt_h,
                        "H=s"  => \$opt_H,   "hostname=s"     => \$opt_H,
                        "C=s"  => \$opt_C,   "community=s"    => \$opt_C,
                        "v"    => \$opt_v,   "verbose"        => \$opt_v,
                        "2"    => \$opt_v2,  "v2c"            => \$opt_v2,
                        "w=s"  => \$opt_w,   "warning=s"      => \$opt_w,
                        "c=s"  => \$opt_c,   "critical=s"     => \$opt_c, 
                        "d=s"  => \$opt_d,   "device=s"       => \$opt_d,
                        "f=s"  => \$opt_f,   "factor=s"       => \$opt_f,
);

if ( $status_getop == 0 ) { 
    print_usage();
    exit $ERRORS{OK};
}

########## Function definition ##########
# the help :-)
sub print_usage () {
    print "Usage: $PROGNAME [-h|--help] [-v|--verbose] -C community [-2] [-f|--factor K|M|G] -H hostname -d diskdevice -w <warning> -c <critical>\n\n";

}

sub print_help () {
    print "\n";
    print_usage();
    print "The script monitor the I/O of device. \n";
    print "   -H (--hostname)   Hostname to query - (required)\n";
    print "   -C (--community)  SNMP read community (required)\n";
    print "                     used with SNMP v1 and v2c\n";
    print "   -v (--verbose)    print extra verbging information\n";
    print "   -2 (--v2c)        2 for SNMP v2c\n";
    print "   -w (--warn)       Signal strength at which a warning message will be generated (required)\n";
    print "   -c (--crit)       Signal strength at which a critical message will be generated (required)\n";
    print "   -d                Device Name (hda, hdb, sda or sdb) (required)\n";
    print "   -f (--factor)     Unit of threshold (K,M,G) Bytes/s (defaults M for MB/s)\n";
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
    unless ($opt_w) {
        print_usage();
        exit $ERRORS{CRITICAL};
    }
    unless ($opt_C) {
        print_usage();
        exit $ERRORS{CRITICAL};
    }
    unless ($opt_c) {
        print_usage();
        exit $ERRORS{CRITICAL};
    }
    unless ($opt_d) {
        print_usage();
        exit $ERRORS{CRITICAL};
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
if ($opt_f) {
    $factor = $opt_f;
} else{
    $factor = "M"
}

verb("Try to connect Host => $HOST, Community => $COMMUNITY, Version => $snmp_version");
(my $session, $error) = Net::SNMP->session(-hostname => $HOST, -community => $COMMUNITY, -version => $snmp_version, -port => 161);

if (!defined($session)) {
   print "ERROR opening session: $error \n";
   print "Unable to connect to $HOST ! Please verify the HOST or the community string : $COMMUNITY.\n";
   exit $ERRORS{"UNKNOWN"};
}
else {
    verb("Session OK");
}


############  Run check ############
my $buffer_file = "/tmp/".$PROGNAME."_".$HOST."_cache";
unless (-e $buffer_file) {


    verb("Search dskIODevice for $opt_d");
    my $response = $session->get_table($dskIODevice);
    if ( !defined($response )) {
        my $answer = $session->error;
        $session->close;
        print("WARNING: SNMP error: $answer\n");
        exit $ERRORS{'WARNING'};
    }
    
    foreach my $key ( sort keys %{$response} ) {
          next if ( $response->{$key} ne $opt_d);  
          verb("Found oid : $key");
          $key =~ /.*\.(\d+)$/;
          my $index_device = $1;
          verb("Index for $opt_d : $index_device");
    
    }

}

