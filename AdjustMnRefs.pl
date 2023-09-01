#!/usr/bin/env perl
my $USAGE = "Usage: $0 [--inifile inifile.ini] [--section AdjustMnRefs] [--logfile logfile.log] [--recmark lx] [--eolrep #] [--reptag __hash__] [--debug] [file.sfm]\n";
=pod
This script is to adjust the main references and flag their corresponding subentry.

The ini file should have sections with syntax like this:
[AdjustMnRefs]
recmark=lx
SubentryMarkers=se
MainREfMarker=mn
SecondMainRefMarker=mnx
SubentryMarkerSuffix=_ref

=cut
use 5.020;
use utf8;
use open qw/:std :utf8/;

use strict;
use warnings;
use English;
use Data::Dumper qw(Dumper);


use File::Basename;
my $scriptname = fileparse($0, qr/\.[^.]*/); # script name without the .pl
$USAGE =~ s/inifile\./$scriptname\./;
$USAGE =~ s/logfile\./$scriptname\./;

use Getopt::Long;
GetOptions (
	'inifile:s'   => \(my $inifilename = "$scriptname.ini"), # ini filename
	'section:s'   => \(my $inisection = "AdjustMnRefs"), # section of ini file to use

	'logfile:s'   => \(my $logfilename = "$scriptname.log"), # log filename
	'help'    => \my $help,
# additional options go here.
# 'sampleoption:s' => \(my $sampleoption = "optiondefault"),
	'recmark:s' => \(my $recmark = "lx"), # record marker, default lx
	'eolrep:s' => \(my $eolrep = "#"), # character used to replace EOL
	'reptag:s' => \(my $reptag = "__hash__"), # tag to use in place of the EOL replacement character
	# e.g., an alternative is --eolrep % --reptag __percent__

	# Be aware # is the bash comment character, so quote it if you want to specify it.
	#	Better yet, just don't specify it -- it's the default.
	'debug'       => \my $debug,
	) or die $USAGE;
if ($help) {
	say STDERR $USAGE;
	exit;
	}

open(my $LOGFILE, '>', $logfilename)
		or die "Could not open Log file '$logfilename' $!";


# check your options and assign their information to variables here

use Config::Tiny;
my $config = Config::Tiny->read($inifilename, 'crlf');
die "Quitting: couldn't find the INI file $inifilename\n$USAGE\n" if !$config;

$recmark = $config->{"$inisection"}->{recmark} if $config->{"$inisection"}->{recmark};
$recmark = clean_marks($recmark); # no backslashes or spaces in record marker

my $hmmark = $config->{"$inisection"}->{homographmark};
say STDERR "Homograph mark:$hmmark" if $debug;
$hmmark = clean_marks($hmmark);

my $semarks = "se";
$semarks = $config->{"$inisection"}->{SubentryMarkers} if $config->{"$inisection"}->{SubentryMarkers};
$semarks = clean_marks($semarks);

my $mnrefmark = "mn";
$mnrefmark = $config->{"$inisection"}->{MainRefMarker} if $config->{"$inisection"}->{MainRefMarker};
$mnrefmark = clean_marks($mnrefmark);

my $altmnrefmark = "mnx";
$altmnrefmark = $config->{"$inisection"}->{AltMainRefMarker} if $config->{"$inisection"}->{AltMainRefMarker};
$altmnrefmark =clean_marks($altmnrefmark);

my $altsubsuffix = "_ref";
$altsubsuffix = $config->{"$inisection"}->{AltSubentrySuffix} if $config->{"$inisection"}->{AltSubentrySuffix};

say STDERR "Record marker:$recmark" if $debug;
say STDERR "Subentry marker:$semarks" if $debug;
say STDERR "Main Ref marker:$mnrefmark" if $debug;
say STDERR "Alternate Main Ref marker:$altmnrefmark" if $debug;
say STDERR "Alternate Subentry Marker Suffix:$altsubsuffix" if $debug;

# die "after options/Config";
# generate array of the input file with one SFM record per line (opl)
my @opledfile_in;
my $line = ""; # accumulated SFM record
my $crlf;
while (<>) {
	$crlf = $MATCH if  s/\R//g;
	s/$eolrep/$reptag/g;
	$_ .= "$eolrep";
	if (/^\\$recmark /) {
		$line =~ s/$eolrep$/$crlf/;
		push @opledfile_in, $line;
		$line = $_;
		}
	else { $line .= $_ }
	}
push @opledfile_in, $line;
say "opledfile array:" if $debug;
say STDERR @opledfile_in if $debug;

my $sizeopl = scalar @opledfile_in;
say STDERR "size opl:", $sizeopl if $debug;

my %oplineno =() ; # build a hash of line numbers of lex/homographs
for (my $oplindex=0; $oplindex < $sizeopl; $oplindex++) {
	next if ! $opledfile_in[$oplindex];
	my $key = getkey($opledfile_in[$oplindex], $recmark, $hmmark);
	$oplineno{$key}= $oplindex;
	}
say "oplineno hash keyed on lexeme/homographs:"  if $debug;
print STDERR Dumper %oplineno  if $debug;
for my $oplline (@opledfile_in) {
	$oplline =~ s/\\$mnrefmark /\\$altmnrefmark /g;
	$oplline =~ s/\\$altmnrefmark /\\$mnrefmark /; # change the first one back
	}
say "opledfile array:" if $debug;
say STDERR @opledfile_in if $debug;

for my $oplline  (@opledfile_in) {
	next if $oplline  !~ /\\$altmnrefmark /;
	my $oplline_key = getkey($oplline, $recmark, $hmmark);
	while  ($oplline  =~ /(\\$altmnrefmark ([^$eolrep]+))/g) {
		my $altmain = $2;
		if (exists $oplineno{$altmain}) {
			say STDERR qq(Line # hash lookup on "$altmain" found:$oplineno{$altmain}) if $debug;
			my $altmainrec = $opledfile_in[$oplineno{$altmain}];
			say STDERR qq(Found Alternate main reference: "$altmainrec") if $debug;
			$altmainrec =~ s/\\($semarks) $oplline_key/\\${1}$altsubsuffix $oplline_key/;
			$opledfile_in[$oplineno{$altmain}] = $altmainrec;
			say STDERR qq(Changed the subentry mark: "$opledfile_in[$oplineno{$altmain}]") if $debug;
			}
		else {
			say $LOGFILE qq(Error: In "$oplline" looked for "\\$altmnrefmark $altmain" and couldn't find it.);
			}
		}
	say STDERR "oplline:", Dumper($oplline) if $debug;
	}
# number the mnx entries starting at 2 (to match FLEx lexical refs EC-2, EC-3, etc.)

for my $oplline (@opledfile_in) {
	my $mnxcount=1;
	$oplline =~ s/\\mnx/$mnxcount++; "$MATCH$mnxcount"/ge;
	}

for my $oplline (@opledfile_in) {
	say STDERR "oplline:", Dumper($oplline) if $debug;
	#de_opl this line
	for ($oplline) {
		$crlf=$MATCH if /\R/;
		s/$eolrep/$crlf/g;
		s/$reptag/$eolrep/g;
		print;
		}
	}

sub clean_marks {
# converts an SFM list into a search string
my ($marks) = @_;
for ($marks) {
	s/\\//g;
	s/ //g;
	s/\,*$//; # no trailing commas
	s/\,/\|/g;  # use bars for or'ing
	}
return $marks;
}

sub getkey{
my ($record,  $recmark, $hmmark) = @_;
=pod
say STDERR "oplline:$record" if $debug;
say STDERR "lx:$recmark" if $debug;
say STDERR "hm:$hmmark" if $debug;
=cut
return 0 if $record !~ m/^\\$recmark\ ([^$eolrep]*)/;
my $buildkey = $1;
say STDERR "lexeme:$buildkey" if $debug;
if ($record =~ m/\\$hmmark\ ([^$eolrep]*)/) {
	$buildkey = $buildkey . $1;
	say STDERR "lex+hm:$buildkey" if $debug;
	}
return $buildkey;
}
