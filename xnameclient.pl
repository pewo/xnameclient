#!/usr/bin/perl -w
#
# xname.pl  -  updates dyndns 
# Written by Peter Wirdemo (peter <dot> wirdemo gmail <dot> com)
# 
#########
# Version
#########
#
# 0.0.2 Thu Dec 27 13:06:20 CET 2018
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
	my($target) = shift;
	return(undef) unless ( $target );
	print "Trying to get port on $target\n" if ( $debug );

	my($port) = 22;
	my(@res) = popen("host -t TXT $target");
	foreach ( @res ) {
		print "Got TXT: $_\n" if ( $debug );
		if ( m/$target/ ) {
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
	

my($server) = undef;
my($hostname) = undef;
GetOptions(
	"server=s",\$server,
	"hostname=s",\$hostname,
	"debug",\$debug,
);

unless ( $server ) {
	die "Usage: $0 --server=<dyndns servername> --hostname=<hostname to update>\n";
}

eval {
	my($lock);
	unless ( open($lock, ">>", $lockfile) ) {
		print "Writing $lockfile: $!\n";
		exit(1);
	}

	local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
	alarm 60;

	print "Locking $lockfile\n" if ( $debug );
	lock($lock);

	unless ( $hostname ) {
		$hostname = hostname;
	}
	unless ( $server ) {
		if ( $hostname =~ /\.xname\.se/ ) {
			$server = "dyndns.xname.se";
		}
	}
	my($port) = getport($server);
	unless ( $port ) {
		die "Can't locate ssh port to our dyndns server(TXT record in DNS), exiting...\n";
	}


	if ( -x $ssh ) {	
		system("$ssh -p $port -o 'StrictHostKeyChecking=no' dyndns\@$server ip.pl --set=$hostname");
	}
	else {
		print "Please install a ssh client before trying this...exiting...\n";
		exit(2);
	}

	alarm 0;

	unlock($lock);
};

if ($@) {
	die unless $@ eq "alarm\n";   # propagate unexpected errors
	# timed out
}
