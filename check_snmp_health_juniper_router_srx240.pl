#!/usr/bin/perl -w
################################################################################
# Copyright (C) 2013 Olivier LI-KIANG-CHEONG                                   #
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


use strict;
use Net::SNMP;
use Getopt::Long;
use Data::Dumper;

my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

my $o_jnxOperatingDescr   = "1.3.6.1.4.1.2636.3.1.13.1.5";
my $o_jnxOperatingCPU     = "1.3.6.1.4.1.2636.3.1.13.1.8";
my $o_jnxOperatingTemp    = "1.3.6.1.4.1.2636.3.1.13.1.7";
my $o_jnxOperatingBuffer  = "1.3.6.1.4.1.2636.3.1.13.1.11";
my $keyword_match = "Routing\ Engine"; # value in o_jnxOperatingDescr to catch cpu index

# Globals
my $Version='1.0';
my $o_verb      = undef;  # verbose mode
my $o_host      = undef;  # hostname
my $o_community = undef;  # community
my $o_version2  = undef;  # use snmp v2c
# SNMPv3 specific
my $o_login     = undef;  # Login for snmpv3
my $o_passwd    = undef;  # Pass for snmpv3
my $o_privpass  = undef;  # priv password
my $v3protocols = undef;  # V3 protocol list.
my $o_authproto = 'md5';  # Auth protocol
my $o_privproto = 'des';  # Priv protocol


#
my $o_port      = 161;    # port
my $o_crit      = undef;  # critical level
my $o_warn      = undef;  # warning level
my $o_mode      = undef;  # mode
my $o_timeout   = undef;  # Timeout (Default 5)
my $o_version   = undef;  # print version
my $o_help      = undef;  # wan't some help ?

sub p_version { print "$0 version : $Version\n"; }

sub print_usage {
    print "Usage: $0 [-v] -H <host> -C <snmp_community> [-2] | (-l login -x passwd [-X pass -L <authp>,<privp>])  [-p <port>] -w <warn level> -c <crit level> -m <cpu-usage|mem-usage|temperature> [-t <timeout>] [-V]\n";
}

sub help {
   print "\nMonitor SNMP Memory JUNIPER ROUTER SRX240 for Nagios version ",$Version,"\n";
   print "GPL licence, (c)2013 Olivier LI-KIANG-CHEONG\n\n";
   print_usage();
   print <<EOT;
-v, --verbose
   print extra debugging information
-H, --hostname
   name or IP address of host to check
-C, --community=COMMUNITY NAME
   community name for the host's SNMP agent (implies v1 protocol)
-2, --v2c
   Use snmp v2c
-l, --login=LOGIN ; -x, --passwd=PASSWD
   Login and auth password for snmpv3 authentication
   If no priv password exists, implies AuthNoPriv
-X, --privpass=PASSWD
   Priv password for snmpv3 (AuthPriv protocol) 
-L, --protocols=<authproto>,<privproto>
   <authproto> : Authentication protocol (md5|sha : default md5)
   <privproto> : Priv protocole (des|aes : default des)
-p, --port=PORT
   SNMP port (Default 161)
-w, --warn=INTEGER
   value check : warning level for cpu in percent (on one minute)
-c, --crit=INTEGER
   critical level for cpu in percent (on one minute)
-t, --timeout=INTEGER
   timeout for SNMP in seconds (Default: 5)
-m, --mode
   A keyword which tells the plugin what to do
      cpu-usage                 (Check the CPU usage of the device)
      mem-usage                 (Check the Memory usage of the device)
      temperature               (Check the temperature)
-V, --version
   prints version number
EOT
}

# For verbose output
sub verb { my $t=shift; print $t,"\n" if defined($o_verb) ; }

sub check_options {
    Getopt::Long::Configure ("bundling");
    GetOptions(
        'v'     => \$o_verb,            'verbose'       => \$o_verb,
        'H:s'   => \$o_host,            'hostname:s'    => \$o_host,
        'C:s'   => \$o_community,       'community:s'   => \$o_community,
        '2'     => \$o_version2,        'v2c'           => \$o_version2,
        'l:s'   => \$o_login,           'login:s'       => \$o_login,
        'x:s'   => \$o_passwd,          'passwd:s'      => \$o_passwd,
        'X:s'   => \$o_privpass,        'privpass:s'    => \$o_privpass,
        'L:s'   => \$v3protocols,       'protocols:s'   => \$v3protocols,
        'p:i'   => \$o_port,            'port:i'        => \$o_port,
        'c:s'   => \$o_crit,            'critical:s'    => \$o_crit,
        'w:s'   => \$o_warn,            'warn:s'        => \$o_warn,
        'm:s'   => \$o_mode,            'mode:s'        => \$o_mode,
        't:i'   => \$o_timeout,         'timeout:i'     => \$o_timeout,
        'V'     => \$o_version,         'version'       => \$o_version,
        'h'     => \$o_help,            'help'          => \$o_help
        );

    # check timeout
    if (defined($o_timeout) && (isnnum($o_timeout) || ($o_timeout < 2) || ($o_timeout > 60))) {
        print "Timeout must be >1 and <60 !\n";
        print_usage(); 
        exit $ERRORS{"UNKNOWN"};
    }
    if (!defined($o_timeout)) {$o_timeout=5;}
    # check help
    if (defined ($o_help) ) { 
        help(); 
        exit $ERRORS{"UNKNOWN"}
    }
    # check version
    if (defined($o_version)) { 
        p_version(); 
        exit $ERRORS{"UNKNOWN"}
    }
    # check host
    if ( ! defined($o_host) ) { # check host and filter
        print_usage(); 
        exit $ERRORS{"UNKNOWN"};
    }
    # check snmp information
    if ( !defined($o_community) && (!defined($o_login) || !defined($o_passwd)) ) { 
        print "Put snmp login info!\n"; print_usage(); exit $ERRORS{"UNKNOWN"};
    }
    if ((defined($o_login) || defined($o_passwd)) && (defined($o_community) || defined($o_version2)) ) { 
        print "Can't mix snmp v1,2c,3 protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"};
    }
    if (defined ($v3protocols)) {
        if (!defined($o_login)) { 
            print "Put snmp V3 login info with protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"};
        }
        my @v3proto=split(/,/,$v3protocols);
        if ((defined ($v3proto[0])) && ($v3proto[0] ne "")) { # Auth protocol
            $o_authproto=$v3proto[0];
        }
        if (defined ($v3proto[1])) { # Priv  protocol
            $o_privproto=$v3proto[1]; 
        }
        if ((defined ($v3proto[1])) && (!defined($o_privpass))) {
            print "Put snmp V3 priv login info with priv protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"};
        }
    }
    # Check warnings and critical
    if (!defined($o_warn) || !defined($o_crit)) { 
        print "put warning and critical info!\n"; print_usage(); exit $ERRORS{"UNKNOWN"};
    }
    # Get rid of % sign
    $o_warn =~ s/\%//g;
    $o_crit =~ s/\%//g;

    # check mode
    if (!defined($o_mode)) {
        print_usage();
        exit $ERRORS{"UNKNOWN"};
    }
    if ($o_mode ne "cpu-usage" && $o_mode ne "mem-usage" && $o_mode ne "temperature") {
        print_usage();
        exit $ERRORS{"UNKNOWN"};
    }

}

########## MAIN #######

check_options();

# Connect to host
my ($session,$error);
if ( defined($o_login) && defined($o_passwd)) {
    # SNMPv3 login
    verb("SNMPv3 login");
    if (!defined ($o_privpass)) {
        verb("SNMPv3 AuthNoPriv login : $o_login, $o_authproto");
        ($session, $error) = Net::SNMP->session(
          -hostname         => $o_host,
          -version          => '3',
          -username         => $o_login,
          -authpassword     => $o_passwd,
          -authprotocol     => $o_authproto,
          -timeout          => $o_timeout
        );
    } else {
        verb("SNMPv3 AuthPriv login : $o_login, $o_authproto, $o_privproto");
        ($session, $error) = Net::SNMP->session(
          -hostname         => $o_host,
          -version          => '3',
          -username         => $o_login,
          -authpassword     => $o_passwd,
          -authprotocol     => $o_authproto,
          -privpassword     => $o_privpass,
          -privprotocol     => $o_privproto,
          -timeout          => $o_timeout
        );
    }
} else {
    if (defined ($o_version2)) {
        # SNMPv2 Login
        verb("SNMP v2c login");
        ($session, $error) = Net::SNMP->session(
             -hostname  => $o_host,
             -version   => 2,
             -community => $o_community,
             -port      => $o_port,
             -timeout   => $o_timeout
        );
    } else {
        # SNMPV1 login
        verb("SNMP v1 login");
        ($session, $error) = Net::SNMP->session(
            -hostname  => $o_host,
            -community => $o_community,
            -port      => $o_port,
            -timeout   => $o_timeout
        );
    }
}

if (!defined($session)) {
    printf("ERROR opening session: %s.\n", $error);
    exit $ERRORS{"UNKNOWN"};
}

my $resultat = (Net::SNMP->VERSION < 4) ?
                  $session->get_table($o_jnxOperatingDescr)
                : $session->get_table(Baseoid => $o_jnxOperatingDescr);

if (!defined($resultat)) {
   printf("ERROR: Description table : %s.\n", $session->error);
   $session->close;
   exit $ERRORS{"UNKNOWN"};
}

if ($o_mode eq "cpu-usage") {
    my %h_cpuoid;
    my $i=0;
    foreach my $key ( sort keys %$resultat) {
       if ($$resultat{$key} =~ /$keyword_match/i ) {
           verb("OID : $key, Desc : $$resultat{$key}");
           $key =~ /$o_jnxOperatingDescr\.(.*)$/ ;
           verb("Index = $1");
           $h_cpuoid{"cpu$i"}= $o_jnxOperatingCPU.".$1";
           $i++;
       }
    }
    #print Dumper \%h_cpuoid;
    
    my @oidlists = values %h_cpuoid;
    $resultat = (Net::SNMP->VERSION < 4) ?
              $session->get_request(@oidlists)
            : $session->get_request(-varbindlist => \@oidlists);
    
    if (!defined($resultat)) {
       printf("ERROR: Description table : %s.\n", $session->error);
       $session->close;
       exit $ERRORS{"UNKNOWN"};
    }
    $session->close;
    
    #print Dumper \$resultat;
    
    my %h_cpuvalue;
    while (my ($key,$value) = each %h_cpuoid) {
        $h_cpuvalue{$key} = $$resultat{$value};
    }
    
    #print Dumper \%h_cpuvalue;
    
    my $perfdata = "";
    my $exit_val = $ERRORS{"OK"};
    my $state = "OK";
    my $message = "";
    foreach my $key ( sort keys %h_cpuvalue) {
        if ($h_cpuvalue{$key} > $o_crit) {
            $exit_val = $ERRORS{"CRITICAL"};
            $state = "CRITICAL";
        } elsif ($h_cpuvalue{$key} > $o_warn) {
            $exit_val = $ERRORS{"WARNING"};
            $state = "WARNING";
        }
        $message .= $key."=".$h_cpuvalue{$key}."% ";
        $perfdata .= $key."=".$h_cpuvalue{$key}."%;$o_warn;$o_crit;0;100 ";
    
    }
    chop $message;
    chop $perfdata;
    print "CPU $state - $message|$perfdata";
    print "\n";
    exit $exit_val;

} elsif ($o_mode eq "mem-usage") {
    my %h_memoid;
    my $i=0;
    foreach my $key ( sort keys %$resultat) {
       if ($$resultat{$key} =~ /$keyword_match/i ) {
           verb("OID : $key, Desc : $$resultat{$key}");
           $key =~ /$o_jnxOperatingDescr\.(.*)$/ ;
           verb("Index = $1");
           $h_memoid{"mem$i"}= $o_jnxOperatingBuffer.".$1";
           $i++;
       }
    }
    #print Dumper \%h_memoid;
    
    my @oidlists = values %h_memoid;
    $resultat = (Net::SNMP->VERSION < 4) ?
              $session->get_request(@oidlists)
            : $session->get_request(-varbindlist => \@oidlists);
    
    if (!defined($resultat)) {
       printf("ERROR: Description table : %s.\n", $session->error);
       $session->close;
       exit $ERRORS{"UNKNOWN"};
    }
    $session->close;
    
    #print Dumper \$resultat;
    
    my %h_cpuvalue;
    while (my ($key,$value) = each %h_memoid) {
        $h_cpuvalue{$key} = $$resultat{$value};
    }
    
    #print Dumper \%h_cpuvalue;
    
    my $perfdata = "";
    my $exit_val = $ERRORS{"OK"};
    my $state = "OK";
    my $message = "";
    foreach my $key ( sort keys %h_cpuvalue) {
        if ($h_cpuvalue{$key} > $o_crit) {
            $exit_val = $ERRORS{"CRITICAL"};
            $state = "CRITICAL";
        } elsif ($h_cpuvalue{$key} > $o_warn) {
            $exit_val = $ERRORS{"WARNING"};
            $state = "WARNING";
        }
        $message .= $key."=".$h_cpuvalue{$key}."% ";
        $perfdata .= $key."=".$h_cpuvalue{$key}."%;$o_warn;$o_crit;0;100 ";
    
    }
    chop $message;
    chop $perfdata;
    print "Memory $state - $message|$perfdata";
    print "\n";
    exit $exit_val;

} elsif ($o_mode eq "temperature") {
    my %h_tempoid;
    my $i=0;
    foreach my $key ( sort keys %$resultat) {
       if ($$resultat{$key} =~ /$keyword_match/i ) {
           verb("OID : $key, Desc : $$resultat{$key}");
           $key =~ /$o_jnxOperatingDescr\.(.*)$/ ;
           verb("Index = $1");
           $h_tempoid{"temp$i"}= $o_jnxOperatingTemp.".$1";
           $i++;
       }
    }
    #print Dumper \%h_tempoid;
    
    my @oidlists = values %h_tempoid;
    $resultat = (Net::SNMP->VERSION < 4) ?
              $session->get_request(@oidlists)
            : $session->get_request(-varbindlist => \@oidlists);
    
    if (!defined($resultat)) {
       printf("ERROR: Description table : %s.\n", $session->error);
       $session->close;
       exit $ERRORS{"UNKNOWN"};
    }
    $session->close;
    
    #print Dumper \$resultat;
    
    my %h_cpuvalue;
    while (my ($key,$value) = each %h_tempoid) {
        $h_cpuvalue{$key} = $$resultat{$value};
    }
    
    #print Dumper \%h_cpuvalue;
    
    my $perfdata = "";
    my $exit_val = $ERRORS{"OK"};
    my $state = "OK";
    my $message = "";
    foreach my $key ( sort keys %h_cpuvalue) {
        if ($h_cpuvalue{$key} > $o_crit) {
            $exit_val = $ERRORS{"CRITICAL"};
            $state = "CRITICAL";
        } elsif ($h_cpuvalue{$key} > $o_warn) {
            $exit_val = $ERRORS{"WARNING"};
            $state = "WARNING";
        }
        $message .= $key."=".$h_cpuvalue{$key}."% ";
        $perfdata .= $key."=".$h_cpuvalue{$key}."%;$o_warn;$o_crit;0;100 ";
    
    }
    chop $message;
    chop $perfdata;
    print "Temperature $state - $message|$perfdata";
    print "\n";
    exit $exit_val;

}
