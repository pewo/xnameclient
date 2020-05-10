#!/usr/bin/perl -w
#
# xname.pl  -  updates dyndns 
# Written by Peter Wirdemo (peter <dot> wirdemo gmail <dot> com)
# 
#########
# Version
#########
#
# 0.0.4 Sun May 10 14:27:51 CEST 2020
# Changed from pewo.xname.se to dyndns.pewo.se
#
# 0.0.3 Thu Dec 27 15:24:23 CET 2018
# https://raw.githubusercontent.com/pewo/xnameclient/master/xnameclient.pl
#
#########
# History
#########
#
##############
# Description: 
##############
#
# Program to update and retrieve ip adresses
# Requires ssh keys on server to update
#
##############

use strict;
use Fcntl qw(:flock);
use Sys::Hostname;
use Getopt::Long;

my($lockfile) = "/tmp/updateip.lock";
my($ssh) = "/usr/bin/ssh";
my($debug) = undef;
my($timeout) = 30;
my($alarm) = $timeout + 10;

sub popen($) {
	my($cmd) = shift;
	return(undef) unless ( $cmd );

	unless ( open(POPEN,"$cmd |") ) {
		print "$cmd: $!\n";
		return();
	}

	my(@res);
	foreach ( <POPEN> ) {
		chomp;
		push(@res,$_);
	}

	close(POPEN);

	return(@res);
}

sub getport($) {
	my($target) = lc(shift);
	return(undef) unless ( $target );
	print "Trying to get port on $target\n" if ( $debug );

	my($port) = 22;
	my(@res) = popen("host -t TXT $target");
	foreach ( @res ) {
		print "Got TXT: $_\n" if ( $debug );
		if ( m/$target/i ) {
			my($test) = $_;
			$test =~ s/\D//g;
			if ( $test && $test > 1024 ) {
				$port = $test;
			}
		}
	}

	if ( $port ) {
		print "Returning $port\n" if ( $debug );
		return($port);
	}
	else {
		print "Returning <undef>\n" if ( $debug );
		return(undef);
	}
}

sub lock {
	my ($fh) = @_;
	flock($fh, LOCK_EX|LOCK_NB) or die "Cannot lock $lockfile - $!\n";
	# and, in case someone appended while we were waiting...
}

sub unlock {
	my ($fh) = @_;
	flock($fh, LOCK_UN) or die "Cannot unlock $lockfile - $!\n";
}

sub dossh {
	my($server) = shift;
	my($hostname) = shift;
	return unless ( defined($server) );

	my($port) = getport($server);
	unless ( $port ) {
		print "Can't locate ssh port to our dyndns server(TXT record in DNS), exiting...\n";
		return(1);
	}

	if ( ! -x $ssh ) {	
		print "Please install a ssh client before trying this...exiting...\n";
		return(2);
	}
	else {
		my($sshcmd) = "$ssh -p $port -o StrictHostKeyChecking=no -o ConnectTimeout=$timeout dyndns\@$server $hostname";
		print "Executing: $sshcmd\n" if ( $debug );
		return(system($sshcmd));
	}
}
	

my($server1) = "dyndns.xname.se";
my($server2) = "dyndns.pewo.se";
my($hostname) = undef;
GetOptions(
	"hostname=s",\$hostname,
	"debug",\$debug,
);


my($lock);
unless ( open($lock, ">>", $lockfile) ) {
	print "Writing $lockfile: $!\n";
	exit(1);
}


print "Locking $lockfile\n" if ( $debug );
lock($lock);

unless ( $hostname ) {
	#$hostname = hostname;
	$hostname = ""; # Lets the ssh key choose which name to update
}

my($error) = 1;
my($server);
foreach $server ( $server1, $server2 ) {
	next unless ( $error );
	print "\nTrying server $server\n" if ( $debug );
	eval {
		local $SIG{ALRM} = sub { die "TIMEOUT\n" }; # NB: \n required
		alarm $alarm;
		$error = dossh($server,$hostname);
		alarm 0;
	};

	print "Error: $error\n" if ( $debug );
	if ($@) {
		die unless $@ eq "TIMEOUT\n";   # propagate unexpected errors
	}
}

unlock($lock);
