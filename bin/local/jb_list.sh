#!/usr/bin/perl -w 

use FindBin;
use lib "$FindBin::Bin/../perl_lib";

use EPrints;
use strict;
use File::Basename;

$|=1;

my $repoid = $ARGV[0];

die "Usage:\n\t" . basename($0) . " <repo_id>\n" if ! $ARGV[0];
my $session = new EPrints::Session( 1 , $repoid , 0 );
if( !defined $session )
{
	print STDERR "Failed to load repository: $repoid\n";
	exit 1;
}

my $eds = $session->dataset( "eprint" );
#my $dds = $session->dataset( "document" );

my $searchexp = new EPrints::Search( 
		session=>$session, 
		dataset=>$eds );

#$searchexp->add_field( $eds->get_field( 'some_field' ), 'match_value' );
$searchexp->add_field( $eds->get_field( 'eprint_status' ), 'archive' );
my $list = $searchexp->perform_search;

#$list->map( sub {
#	my( $session, $dataset, $doc ) = @_;
#	my $eprint = $doc->get_eprint;
#	return unless $eprint->get_value( "eprint_status" ) eq "archive";
#
#	$doc->set_value( "security", "public" );
#	$doc->set_value( "date_embargo", undef );
#	$doc->commit;
#	$eprint->commit;
#	$eprint->generate_static;
#} );

my $info = {
	count => 0,
	ext => {
		_no_ext_ => 0
	},
	issue => [],
};

$list->map( sub {
	my( $session, $dataset, $item, $info ) = @_;
	my @docs = $item->get_all_documents;
	foreach my $doc ( @docs )
	{
		if ( $doc->get_value('main') )
		{
			if ( $doc->get_value('main') =~ /\.([^\.]+)$/ )
			{
				my $ext = lc( $1 );
				$info->{ext}->{$ext} = 0 if ! exists($info->{ext}->{$ext});
				$info->{ext}->{$ext} ++;
			}
			else
			{
				$info->{ext}->{_no_ext_} ++;
			}
		}
		else
		{
			push @{$info->{issue}}, "Eprint ID: " . $item->get_id . "  Doc ID: " . $doc->get_id . " has no 'main' value\n";
		}
	}
	print "Eprint ID: " . $item->get_id . "\tNum docs: " . scalar(@docs) . "\n" if ! scalar(@docs);
	$info->{count} += scalar(@docs);
}, $info );

print "\nTotal docs: " . $info->{count} . "\n";

print "\n*** EXTENSIONS ***\n";
foreach ( sort keys %{$info->{ext}} )
{
	print "$_: " . $info->{ext}->{$_} . "\n";
}

if ( scalar( @{$info->{issue}} ) > 0 )
{
	print "\n*** ISSUES ***\n";
	foreach ( @{$info->{issue}} )
	{
		print $_;
	}
}

$session->terminate();