#!/usr/bin/perl -w 

use FindBin;
use lib "$FindBin::Bin/../perl_lib";

use EPrints;
use strict;
use File::Basename;
use Data::Dumper;

# these stop the warnings for "bad" chars in the titles
use charnames ':full';
binmode(STDOUT, ":utf8");

my $VERSION = '1.0.0 (JB 19/05/2017)';
$|=1;

my $repoid = $ARGV[0];
my $show_totals = ( $ARGV[1] && ( $ARGV[1] eq "verbose" )) ? 1 : 0;

die "Usage:\n\t" . basename($0) . " <repo_id> [<verbose>]\n" if ! $ARGV[0];
my $repo = new EPrints::Session( 1 , $repoid , 0 );
if( !defined $repo )
{
	print STDERR "Failed to load repository: $repoid\n";
	exit 1;
}

####$repo->send_http_header( content_type=>"text/plain; charset=UTF-8" );

my $tsize = 0;
my $totaldocs = 0;
my $totalfiles = 0;
my $filelist = [];

# get archive virtual dataset (i.e. only live eprints)
my $ds = $repo->dataset( 'archive' ) ;
if( !defined $ds )
{
	print STDERR "Unknown Dataset ID: archive\n";
	$repo->terminate;
	exit 1;
}

my $list = $ds->search;
my $n = $list->count;
my @eprints = $list->slice;

foreach my $eprint ( @eprints )
{
	my $esize = 0;
	#foreach my $doc ( @{$eprint->get_value("documents")} ) # this gets thumbnails too
	my @docs = $eprint->get_all_documents;
	my $numdocs = 0;
	foreach my $doc ( @docs )
	{
		$numdocs++;
		my $dsize = 0;

#		my %files = $doc->files;
#		foreach my $key ( keys %files )
#		{
#			#print "$key : $files{$key}\n";
#			$dsize += $files{$key};
#			$totalfiles++;
#			push @$filelist, $doc->local_path . "/$key";
#		}

		my @files = $doc->get_value('files');
		foreach $file ( @files )
		{
			my $fsize = $file->get_value('filesize');
			$dsize += $fsize;
			my $fhash = $file->get_value('hash');
			$totalfiles++;
			push @$filelist, "$fhash\t$fsize\t" . $doc->local_path . $file->get_value('filename');
		}


		#print $doc->get_value("main") . "   " . "\n";
		$esize += $dsize;
	}
	$tsize += $esize;
	$totaldocs += $numdocs;
	####print sprintf("%5d %3d %14d %.54s\n", $eprint->id, $numdocs, $esize, $eprint->get_value("title"));
}


foreach my $file ( @$filelist ) {
	print "$file\n";
}

####print scalar( @$filelist ) . "\n";;
print "eprints:$n,docs:$totaldocs,files:$totalfiles,datavol:$tsize,eversion:"
	. EPrints->human_version . ",fversion:$VERSION\n"
	if $show_totals;

$repo->terminate;

exit;


