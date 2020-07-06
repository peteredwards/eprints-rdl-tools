=head1 NAME

B<xmlfilechecker.pl> - A very quick and dirty checker of file references within EPrints XML files 

=head1 USAGE

xmlfilechecker.pl [-p] [-r] [-g] [-v] [-a <path_add>] [-x <path_exc>] <xml_source>

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
use URI::Escape;
Getopt::Long::Configure ('bundling');



# SOME SETTINGS
my $version = 1.2;
my $vdate = '22/07/2016';
my $debug = 0;

my $extension = 'xml';
my @extensions = qw(.XML .XMl .XmL .xML .Xml .xMl .xmL .xml);
my $logext = 'log';

my %opt = (
	help			=> 0,	# default value for help flag
	no_log			=> 0,	# default value for no_log flag
	no_hash			=> 0,	# default value for no_hash flag
	path_add		=> '',	# default path addition string
	path_exclude	=> '',	# default path exclusion string
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
	duplicates => 0,
);

my $err2null;
my $err2stdout;
my $slash;
my $logbasename;
my %filepath;

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
				my $raw_path = uri_unescape($1);
				# ignore full path if no_path option supplied and use path of XML file instead
				my $target = ($opt{no_path}) ? $fullpath.$slash.basename($raw_path) : $raw_path;
				if ( ! exists $filepath{$raw_path} ) {
					$filepath{$raw_path} = 1;
				}
				else {
					$filepath{$raw_path}++;
					$count{duplicates}++;
					pout("WARNING: File $raw_path referenced $filepath{$raw_path} times\n");
				}
				if ( ! $opt{no_path} ) {
					$target =~ s/^$opt{path_exc}// if $opt{path_exc};
					$target = $opt{path_add} . $target;
				}
				if (-f $target) {
					pout ("Found: $target\n") if $debug;
					$count{found}++;
				}
				else {
					pout ("NOT FOUND: $target\n");
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
		print "\nUsage:\n\n ".basename($0)." [-pgrv] [-a <path_add>] [-x <path_exc>] <xml_source>\n";
		print "   -a = add <path_add> to all file paths (ignored if -f option supplied)\n";
		print "   -x = remove <p_exc> from all file paths (ignored if -f option supplied)\n";
		print "   -p = ignore file paths (all files must be in same folder as XML file)\n";		
		print "   -g = disable log output\n";
		print "   -r = recurse all sub-folders (ignored if <xml_source> is a single file)\n";
		print "   -v = show version number\n\n";
		print "Notes:\n\n The -a and -x options require leading or trailing slashes of the correct type\n\n";
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
			'p' => \$opt{no_path},
			'g' => \$opt{no_log},
			'r' => \$opt{recursion},	
			'v' => \$opt{version},
			'a=s' => \$opt{path_add},
			'x=s' => \$opt{path_exc},
);

$err2null = ($^O eq 'linux' || $^O eq 'darwin') ? '2>/dev/null' : '2>NUL';
$err2stdout = ($^O eq 'linux' || $^O eq 'darwin') ? '2>&1' : '2>&1';
$slash = ($^O eq 'linux' || $^O eq 'darwin') ? '/' : '\\'; # not required but belt and braces

if ($opt{help}) {
	show_usage;
	exit;
}

if ($opt{version}) {
	print "\n" . basename($0) . " - v$version\n\n";
	print "j.beaman\@leeds.ac.uk\n\n";
	exit;
}

if ( $#ARGV != 0 ) {
	show_usage;
	exit 1;
}

# supplied argument needs to be either a valid path or a single file
$rootpath = $ARGV[0];
if ( ! -d $rootpath && ! -f $rootpath ) {
	print "\nERROR: XML source \"$rootpath\" cannot be found!\n";
	show_usage;
	exit 1;
}

my $logpath;

# if supplied argument is a single file
if ( -f $rootpath ) {
	# file name should have an XML extension
	if ( $rootpath !~ /\.$extension$/i ) {
		print "\nERROR: the file \"$rootpath\" should be an XML file!\n";
		exit 1;
	}
	# if so, set the log file path appropriately
	else {
		$logpath = dirname( $rootpath );
	}
}

# if supplied argument is a path, set the log file path to that
$logpath = $rootpath if ( -d $rootpath );

# bit inefficient if both log and hash files are not going to be used...
# using basename here is more reliable than using $0
$logbasename = basename(__FILE__, ('.pl','.PL','.Pl','.pL')).'_'.timestring();

if ( ! $opt{no_log} ) {
	my $logfilename = $logpath.$slash.$logbasename.'.log';
	open (LOGFILE, ">$logfilename");
}

# if we are dealing with a path, look for XML files, then process them
if ( -d $rootpath ) {
	# if searching for XML files recursively
	if ($opt{recursion}) {
		#find(\&process_file, @DIRLIST);
		#find(\&do_find, $rootpath);
		find({ wanted => \&do_check, no_chdir => 1 }, $rootpath);
	}
	# otherwise just look in top folder of supplied path
	else {
		opendir (DIR, "$rootpath") or die $!;
		foreach my $file (sort readdir(DIR)) {
			check_file($rootpath.$slash.$file);
		}
		closedir(DIR);
	}
}

# if we are dealing with a single file
if ( -f $rootpath ) {
		check_file($rootpath);
}

if ( $count{totalxml} ) {
	pout("\nFound $count{found} out of $count{total} files listed in $count{totalxml} XML files\n");
	pout("\nThere were $count{missing} files NOT found.\n") if $count{missing};
	pout("\nThere were $count{duplicates} duplicated file references.\n") if $count{duplicates};
}
else {
	pout("\nCould not find any XML files to process!\n");
}
close(LOGFILE) if ( !$opt{no_log} );

exit 1 if $count{missing};
