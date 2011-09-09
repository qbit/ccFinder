#!/usr/bin/env perl
#
# Aaron Bieber - 09/05/08
# This will plow through a fs 
# looking for files that contain Credit Card numbers
# it uses a version of http://search.cpan.org/~tayers/Algorithm-LUHN-1.00/LUHN.pm ( i think - can't remember )
# had to move the perl module into the script because installing the module was impossible
# VERSION 1.2

use strict;
use warnings;
use Exporter;
use bytes;
use Date::Format;
use File::Find;

#these are for the Algorithm"
use vars qw/$VERSION @ISA @EXPORT @EXPORT_OK $ERROR/;
@ISA       = qw/Exporter/;
@EXPORT    = qw//;
@EXPORT_OK = qw/check_digit is_valid valid_chars/;

$VERSION = '1.0';

my %map = map { $_ => $_ } 0..9;

# user defined stuff
my $emailto = 'fitst.last@pewpew.com';
my $subject = "Output of ccFinder ";
my $file_pattern = "txt|log|xml"; # Change this to any file extension you want to locate
my $ignore_pattern = ".snapshot"; # Change this to anything you want to be ignored
my $mounts = `mount |grep ntap |egrep -v 'superfs' |awk '{ print \$3}'`; # Change this to any file system you want

my $hostname = GetHostname();
my $logging = 1; # set to zero for no logging ( will just print to stdout )
our $logfile = "$hostname-" . time2str("%m-%d-%Y", time) . ".csv";
if ($logging == 1) {
    open LOGFILE, ">>$logfile"; 
}


my $CCRegex = qw/(^(4|5)\d{3}-?\d{4}-?\d{4}-?\d{4}|(4|5)\d{15})|(^(6011)-?\d{4}-?\d{4}-?\d{4}|(6011)-?\d{12})|(^((3\d{3}))-\d{6}-\d{5}|^((3\d{14})))/;
my @search_path = split(/\n/, $mounts);

# ---------------- Main ---------------
#

my $length = @search_path;
foreach my $path (@search_path) {
    print "Searching in $path\n";
    find (\&d, $path);
    $length--;
    if($length == 0) {
        close LOGFILE;
        my $file_length = `cat $logfile | wc -l`;
        if ($file_length == 0) {
            print "Nothing Found!";
            system("echo 'Nothing Found' | mailx -s '$subject ($file_length issues found)' $emailto"); 
        } else {
            system("zip -r $logfile.zippy $logfile ; uuencode $logfile.zippy $logfile.zippy | mailx -s '$subject ($file_length issues found)' $emailto ; rm $logfile.zippy");
        }
    }
    
}

#--------------------_SUBS--------------------
sub logit{
    if ($logging) {
        print LOGFILE "$_[0]\n";
    }
}

sub d {
    my $file = $File::Find::name;
    my $count = 0;
    return if $file =~ /$ignore_pattern/;
    return unless $file =~ /$file_pattern/;
    return if (-l $file);

    open F, $file or print "Couldn't open $file\n" && return;

    while (<F>) {
        if (my ($cc) = m/$CCRegex/o) {
            next unless defined $cc;
            if ($count eq "1") { next; }
            my $string = $hostname . "," . $file . "," . MaskCC($cc);
            print $string, "\n";
            logit($string);
            $count++;
        }
    }
    close F
}

sub MaskCC {
    chomp;
    my $n = shift;
    next unless defined $n;
    my $ccString = SortCC($n);
    if (CheckValidity($ccString)) {
        $ccString =~ s/\d{12}$/XXXXXXXXXXXX/g;
        return $ccString;
    } else {
        return "False Positive";
    }
}

sub SortCC {
    chomp;
    my $c = shift;
    $c =~ s/ //g;
    $c =~ s/-//g;
    return $c;
}

sub CheckValidity {
    my $digit = shift;
    my $checksum = check_digit($digit);
    return "Valid" if (is_valid($digit, $checksum));
}

sub GetHostname {
    use Sys::Hostname;
    my $hn = hostname();
    $hn = (split(/\./, $hn))[0];
    return ($hn);
}

#---------------Algorithm subs----------------------
sub is_valid {
  my $N = shift;
  my $c = check_digit(substr($N, 0,length($N)-1));
  if (defined $c) {
    if (substr($N,length($N)-1, 1) eq $c) {
      return 1;
    } else {
      $ERROR = "Check digit incorrect. Expected $c";
      return '';
    }
  } else {
     #$ERROR will have been set by check_digit
    return '';
  }
}

sub check_digit {
  my @buf = reverse split //, shift;

  my $totalVal = 0;
  my $flip = 1;
  foreach my $c (@buf) {
    unless (exists $map{$c}) {
      $ERROR = "Invalid character, '$c', in check_digit calculation";
      return;
    }
    my $posVal = $map{$c};

    $posVal *= 2 unless $flip = !$flip;

    while ($posVal) {
      $totalVal += $posVal % 10;
      $posVal = int($posVal / 10);
    }
  }

  return (10 - $totalVal % 10) % 10;
}

sub valid_chars {
  return %map unless @_;
  while (@_) {
    my ($k, $v) = splice @_, 0, 2;
    $map{$k} = $v;
  }
}

sub _dump_map {
  my %foo = valid_chars();
  my ($k,$v);
  print "$k => $v\n" while (($k, $v) = each %foo);
}
