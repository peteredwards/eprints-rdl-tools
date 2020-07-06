=head1 NAME

B<xmlfilechecker.pl> - A very quick and dirty checker of file references within EPrints XML files 

=head1 USAGE

xmlfilechecker.pl [-g] [-h] [-l] [-r] [-v] <source_path>

=cut

use strict;
use warnings;

use File::Find;
use File::Basename;
use File::Copy;
use Getopt::Long;

use File::Spec;
use Digest::MD5;
use File::Path qw(make_path remove_tree);
Getopt::Long::Configure ('bundling');


# SOME SETTINGS
my $version = 1.0;
my $vdate = '20/01/2015';
my $debug = 1;

my $extension = 'xml';
my @extensions = qw(.XML .XMl .XmL .xML .Xml .xMl .xmL .xml);
my $logext = 'log';

my %opt = (
	help			=> 0,	# default value for help flag
	no_log			=> 0,	# default value for no_log flag
	no_hash			=> 0,	# default value for no_hash flag
	recursion		=> 0,	# defualt value for recursion flag
	verbose			=> 0,	# default value of verbose flag
	version			=> 0,	# default value of version flag
);


# SOME INITIALISATIONS
my $rootpath = '';

my %count = (
	totalxml => 0,
	total	=> 0,
	found	=> 0,
	missing	=> 0,
);

my $err2null;
my $err2stdout;
my $slash;
my $logbasename;


############################################

sub do_check {

=head2 do_check

Wrapper function for checking of all files in the list

=cut

	check_file($File::Find::name);
}


sub check_file {

=head2 check_file

Perform check of file paths listed within an Eprints XML file

=cut

	my $ffile = shift;
	my $fullpath = dirname($ffile);
	my $basename = basename($ffile,@extensions);
	
	if (-f $ffile and $ffile =~ /\.$extension$/i) {
		my $ip_filename = ($opt{recursion}) ? $ffile : basename($ffile);
		$count{totalxml}++;
		pout ("Checking $ffile ($count{totalxml})\n") if $debug;
		open FILE, $ffile or die "\nERROR: Cannot open file $ffile\n\n";
		while (<FILE>) {
			chomp;
			if ($_ =~ /<url>file:\/\/(.*?)<\/url>/) {
				$count{total}++;
				if (-f $1) {
					pout ("Found: $1\n") if $debug;
					$count{found}++;
				}
				else {
					pout ("NOT FOUND: $1\n");
					$count{missing}++;
				}
			} 
		}
	}
}

sub show_usage {

=head2 show_usage

Shows usage information.

=cut
	if ($opt{help} || ! $opt{no_usage}) {
		print "\nUsage:\n\n ".basename($0)." [-ghrv] <source_path>\n";
		print "   -g = disable log output\n";
		print "   -h = disable hash calculations\n";
		print "   -r = recurse all sub-folders\n";
		print "   -v = show version number\n\n";
		print "Author:\n\n John Beaman - j.beaman\@leeds.ac.uk\n\n";
	}
}


sub timestring {

=head2 timestring

Outputs a time string for log file use

=cut

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	return sprintf("%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
}

sub pout {

=head2 pout

Outputs text to STDOUT and/or log file depending on command line options

=cut

	my $msg = shift;
	print $msg if ! $opt{no_output};
	print LOGFILE timestring().' '.$msg if ! $opt{no_log};

}

sub do_hash {

=head2 do_hash

Calculates MD5 hash of file and outputs it to hash file residing in same folder

=cut

	my $hashfile = shift;
	my $hashfolder = shift;
	
	my $hashfilename = $hashfolder.$slash.$logbasename.'_md5.txt';
	my $hashipf = $hashfolder.$slash.$hashfile;
	
	open (HASHFILE, ">>$hashfilename") or die "Can't open hash file '$hashfilename': $!";
	open (my $fh, '<', $hashipf) or die "Can't open '$hashipf' for hashing: $!";
	binmode ($fh);
	my $hash = Digest::MD5->new->addfile($fh)->hexdigest;
	print HASHFILE "$hash\t$hashfile\n";
	close($fh);
	close(HASHFILE);
}



#####################################
$|++;

GetOptions ('help|?' => \$opt{help},
			'g' => \$opt{no_log},
			'h' => \$opt{no_hash},
			'r' => \$opt{recursion},	
			'v' => \$opt{version},
);

$err2null = ($^O eq 'linux' || $^O eq 'darwin') ? '2>/dev/null' : '2>NUL';
$err2stdout = ($^O eq 'linux' || $^O eq 'darwin') ? '2>&1' : '2>&1';
$slash = ($^O eq 'linux' || $^O eq 'darwin') ? '/' : '\\'; # not required but belt and braces

if ($opt{help}) {
	show_usage;
	exit;
}

if ($opt{version}) {
	print "$version\n";
	exit;
}

if ( $#ARGV != 0 ) {
	show_usage;
	exit;
}

$rootpath = $ARGV[0];
if (! -d $rootpath) {
	print "\nERROR: Source path \"$rootpath\" cannot be found!\n";
	show_usage;
	exit;
}


# bit inefficient if both log and hash files are not going to be used...
# using basename here is more reliable than using $0
$logbasename = basename(__FILE__, ('.pl','.PL','.Pl','.pL')).'_'.timestring();

if ( ! $opt{no_log} ) {
	my $logpath = $rootpath;
	my $logfilename = $logpath.$slash.$logbasename.'.log';
	open (LOGFILE, ">$logfilename");
}

if ($opt{recursion}) {
	#find(\&process_file, @DIRLIST);
	#find(\&do_find, $rootpath);
	find({ wanted => \&do_check, no_chdir => 1 }, $rootpath);
}
else {
	opendir (DIR, "$rootpath") or die $!;
	foreach my $file (sort readdir(DIR)) {
		check_file($rootpath.$slash.$file);
	}
	closedir(DIR);
}

pout("\nFound $count{found} out of $count{total} files listed $count{totalxml} XML files\n");
pout("\nThere were $count{missing} files NOT found.\n") if $count{missing};

close(LOGFILE) if ( !$opt{no_log} );

