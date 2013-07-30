#!/usr/bin/perl

#    ibxMoveCnameToHost.pl - Merge orphaned CNAME records into Host records.
#    Copyright (C) 2013 Jason E. Murray
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.


use strict;
use Getopt::Long;
use Data::Dumper;
use Infoblox;
use Term::Prompt;
use Pod::Usage;
use Net::DNS;

# Global Command line arguments
my $gm;
my $user;
my $pass;
my $debug;
my $host;
my $timeout;
my $modify;
my $help = 0;
my $dnsserver;

# Get Options
GetOptions(
    "g|gm:s"      => \$gm,
    "u|user:s"    => \$user,
    "p|pass:s"    => \$pass,
    "h|host:s"    => \$host,
    "dns:s"		  => \$dnsserver,
    "d|debug"     => \$debug,
    "t|timeout:i" => \$timeout,
    "m|modify"    => \$modify,
    "help|?"	  => \$help
);

# Validate command-line arguments and options
if ( !defined $gm || !defined $host || !defined $dnsserver   ) {
	pod2usage(-verbose => 1);
}
pod2usage(-verbose => 2) if $help;

$user    = defined $user    ? $user    : "admin";
$timeout = defined $timeout ? $timeout : 900;
$pass = prompt( 'p', "password for user [$user]: ", '', '' );
print "\n";
$host = substr($host,0,-1) if substr($host,-1) eq ".";


sub verifyDns {
	my ($cname_record) = @_;
	
	print "DEBUG: entering DNS verification\n" if $debug == 1;
	
	# Set options in the constructor
	my $res = Net::DNS::Resolver->new(
		nameservers => [($dnsserver)],
		recurse     => 0,
		debug       => 0,
	);
		
	my $packet = $res->send($cname_record, 'CNAME');
	my @answer = $packet->answer;
	
	if (@answer) {
		foreach my $rr (@answer) {
			if ( $rr->name ne $cname_record) {
				die "Moving $cname_record / $rr->name failed DNS verification, script aborted!  $cname_record is probably broken!  Manually fix!\n";
			}
			print "DEBUG DNS: Looking up $cname_record, returned $rr->name - Everything Looks OK so far\n" if $debug == 1;
		}
	} else {
		die "Moving $cname_record failed DNS verification, script aborted!  $cname_record is probably broken!  Manually fix!\n";
	}
}


# get an Infoblox Session handle
my $session = Infoblox::Session->new(
    master   => $gm,
    username => $user,
    password => $pass,
    timeout  => $timeout
);
die( $session->status_detail ) if $session->status_code();

my @host_objs = $session->get(
	object => "Infoblox::DNS::Host",
	name   => $host
);
my $host_obj = $host_objs[0];
 
if ($host_obj) {
	print "\nFound host record: $host\n";
	# dereference array and returns elements
	foreach my $alias ( @{$host_obj->aliases()} ) {
		printf "\tExisting HOST aliases: %s\n", $alias;
 	}
 	
	my @cname_objs = $session->search(
	    object => "Infoblox::DNS::Record::CNAME",
	    name   => ".*",
	    canonical => $host
	);

	printf "\t%s CNAME objects can be merged into %s:\n", scalar @cname_objs, $host;

	foreach my $cname_obj (@cname_objs) {
	    my $canonical_name = $cname_obj->canonical();
	    my $cname_record          = $cname_obj->name();
	    printf "\t\tStandalone CNAME record: %s\n" , $cname_record;    
	    
	    # Push the CNAME on the HOST records aliases object
	    push (@{$host_obj->aliases()}, $cname_record);
	    
	    # Debug the objects found or modified
	    print Dumper($host_obj->aliases()) if $debug == 1;
		print Dumper($cname_obj->name()) if $debug == 1;
		
		# modify records
		if ( defined $modify) {
			print "--> Removing cname: $cname_record: ";
			$session->remove( $cname_obj ) or die("Remove record $cname_record CNAME failed: ", $session->status_code() . ":" . $session->status_detail());
			print "SUCCESS\n";
			
			print "++> Adding alias: $cname_record: ";
			$session->modify( $host_obj ) or die("Modify host record $cname_record failed: ", $session->status_code() . ":" . $session->status_detail());
			print "SUCCESS\n";
			
			# Verify DNS is still resolving the CNAME after the move.  Bail out if it does not.
			sleep(5);
			verifyDns($cname_record);
		}
	}	
 	
} else {
	print "Host record not found for: $host\n";
}

__END__

=head1 NAME

ibxMoveCnameToHost.pl - Merge standalone CNAME records into Host aliases tab

=head1 SYNOPSIS

ibxMoveCnameToHost.pl [options] -g <grid master> --dns <your-master-dns-server> -h <host record>

=head1 OPTIONS

=over 8

=item B<-g>

FQDN of GRID Master

=item B<--dns>

IP address of your primary DNS server.   You want to make sure this is the authoritative DNS server.   You don't want to use a caching server!

=item B<-u>

username

=item B<-p>

password (leave this blank to be prompted)

=item B<-h> 

FQDN of Host record

=item B<-m>

Merge the CNAMES into the Host record.   Without this option it only displays what could be merged.

=item B<-t>

Change session timeout

=item B<--debug>

Enable full debug messages

=item B<--help>

Display full help menu

=back

=head1 DESCRIPTION

B<This program> will merge standalone CNAME records into the Host aliases tab.

=cut 
