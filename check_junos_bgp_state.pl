#! /usr/bin/perl
################################################################################
# 2013 Olivier LI-KIANG-CHEONG                                                 #
#                                                                              #
# This program is free software; you can redistribute it and/or modify         #
# it under the terms of the GNU General Public License as published by         #
# the Free Software Foundation; either version 2 of the License, or            #
# (at your option) any later version.                                          #
#                                                                              #
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY; without even the implied warranty of               #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
# GNU General Public License for more details.                                 #
#                                                                              #
# You should have received a copy of the GNU General Public License along      #
# with this program; if not, write to the Free Software Foundation, Inc.,      #
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.                  #
#                                                                              #
################################################################################
# Version : 1.0                                                                #
################################################################################
# Author : Olivier LI-KIANG-CHEONG <lkco@gezen.fr>                             #
################################################################################
# CHANGELOG :                                                                  #
# 1.0 : initial release                                                        #
################################################################################
# DESCRIPTION :                                                                #
# Nagios plugin : Check BGP State(Simple) on Juniper router                    #
# verifies thet BGP connections are established                                #
# If not, and enabled,  CRITICAL alarm will be triggered                       #
# Hardcoded for SNMP version 2c for now.                                       #
# Tested on : Juniper SRX240                                                   #
################################################################################

use strict;
use warnings;

use Net::SNMP qw(:snmp);
use Getopt::Long;
&Getopt::Long::config('auto_abbrev');
use Net::IP;

my $version = "1.0";
my $TIMEOUT = 10;
my $snmp_domain="udp/ipv4";
my $snmp_version="v2c";
# default return value is UNKNOWN
my $state = "UNKNOWN";
my $status;
my $needhelp;
my $answer;
my $output = "";
my $output_OK = "";
my $session;
my $error;


my %ERRORS = (
    'OK'       => '0',
    'WARNING'  => '1',
    'CRITICAL' => '2',
    'UNKNOWN'  => '3',
);

# external variable declarations
my $hostname;
my $community = "public";
my $port = 161;

# OID definitions
my $bgp_peer_state_oid         = '1.3.6.1.4.1.2636.5.1.1.2.1.1.1.2';
my $bgp_peer_admin_status_oid  = '1.3.6.1.4.1.2636.5.1.1.2.1.1.1.3';
#BGP states
my @bgp_peer_state_text        = ("None","Idle","Connect","Active","Opensent","Openconfirm","Established");
my @bgp_peer_state             = (0,1,2,3,4,5,6);

# Just in case of problems, let's not hang NAGIOS
$SIG{'ALRM'} = sub {
    print ("UNKNOWN: No snmp response from $hostname\n");
    exit $ERRORS{"UNKNOWN"};
};
alarm($TIMEOUT);

if (scalar(@ARGV) == 0) {
    usage();
} 

Getopt::Long::Configure("no_ignore_case");
$status = GetOptions(
    "h|help"              => \$needhelp,
    "C|snmpcommunity=s"   => \$community,
    "p|port=i"            => \$port,
    "H|hostip=s"          => \$hostname,
    "d|snmpdomain=s"      => \$snmp_domain,
);

if ($status == 0 || $needhelp) {
    usage();
} # end if getting options fails or the user wants help

if (!defined($hostname)) {
    $state = "UNKNOWN";
    $answer = "Host IP must be specified";
    print "$state: $answer\n";
    exit $ERRORS{$state};
} # end check for host IP

#Define SNMP session
($session, $error) = Net::SNMP->session(
    -domain       => $snmp_domain,
    -hostname     => shift || $hostname,
    -community    => shift || $community,
    -nonblocking  => 0,
    -translate    => [-octetstring => 0],
    -version      => $snmp_version,
);

my $critical = "";
my $OK = "";
my @octets;

# Do the SNMP queries
my $result_bgp_state        = $session->get_table(Baseoid => $bgp_peer_state_oid );
my $result_bgp_admin_status = $session->get_table(Baseoid => $bgp_peer_admin_status_oid );
# Check if we got anything back
if ( !defined($result_bgp_state) || !defined($result_bgp_admin_status) ) {
    # If no such OID exists
    $session->close;
    print "BGP Not Configured : OK\n";
    exit $ERRORS{"OK"};
}
# Loop through BGP admin status
my $i=0;
my @bgp_admin_status;
foreach my $key1 ( sort (keys %$result_bgp_admin_status)) {
    $bgp_admin_status[$i] = $$result_bgp_admin_status{$key1};
    $i++;
}
	
$i=0;
my $peer_ip;
my $hex;
my $establised_bgp_peers=0;
foreach my $key ( sort(keys %$result_bgp_state)) {
    @octets=split (/\./,$key);
    #check if it's IPv6 peer
    if ( scalar(@octets) > 26 ) {
        my @octets_hex;
        foreach my $dec (@octets) {
            $hex = sprintf ("%lx", $dec);
            if ( length($hex) < 2 ) {
                $hex= 0 . $hex;
            }
            push(@octets_hex,$hex);
        }
        $peer_ip = "$octets_hex[34]$octets_hex[35]:$octets_hex[36]$octets_hex[37]";
        $peer_ip .= ":$octets_hex[38]$octets_hex[39]:$octets_hex[40]$octets_hex[41]";
        $peer_ip .= ":$octets_hex[42]$octets_hex[43]:$octets_hex[44]$octets_hex[45]";
        $peer_ip .= ":$octets_hex[46]$octets_hex[47]:$octets_hex[48]$octets_hex[49]";
        $peer_ip = Net::IP::ip_compress_address($peer_ip, 6);
    }
    else {
        $peer_ip = "$octets[22].$octets[23].$octets[24].$octets[25]";
    }
    #print "$peer_ip\n";
    #print $$result_bgp_state{$key};
    #Check if state is Established
    if ( ($$result_bgp_state{$key}) lt 6) {
        # Check if manually shutdown/disabled
        if ( $bgp_admin_status[$i] eq "1" ) {
            $OK="yes";
            $output_OK .= " peer '$peer_ip' is Shutdown,";
        }
        # Not manually shutdown/disabled
        else {	
            $critical = "yes";
            $output .= " peer '$peer_ip' is ".$bgp_peer_state_text[$$result_bgp_state{$key}].",";
        }
    }
    else {
        $establised_bgp_peers++;
        $OK="yes";
        $output_OK .= " peer '$peer_ip' is ".$bgp_peer_state_text[$$result_bgp_state{$key}].",";
    }
    $i++;		
}
$session->close;

# Print the results
chop $output;
chop $output_OK;
if ($critical eq "yes") {
    print "CRITICAL -".$output."| bgp_peers=$establised_bgp_peers\n";
    exit $ERRORS{"CRITICAL"};
}

if ($OK eq "yes") {
    print "All BGP Neighbors are OK -".$output_OK."|bgp_peers=$establised_bgp_peers\n";
    exit $ERRORS{"OK"};
}


# the usage of this program
sub usage
{
    print <<END;
== check_junos_bgp_state.pl v$version ==
Perl Juniper JunOS SNMP BGP status check plugin for Nagios

Usage:
  check_junos_bgp_state.pl (-C|--snmpcommunity) <read_community>
                     (-H|--host IP address) <host ip>
                     [-p|--port] <port>
                     [-d|--snmp-domain] <udp/ipv4>

END
    exit $ERRORS{"UNKNOWN"};
}


