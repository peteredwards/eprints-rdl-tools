#	ASSUMPTIONS
#	Compound fields must have all sub-field values listed on the same line of the spreadsheet
#	Compound fields cannot have compound sub-fields
#	Creators is a special case of compound field (treated like documents) so can have compounds within it
#	Creators should always be a multiple field
#	Document path field is special and is always multiple and part of the documents data section (PUT CHECK IN)
#	Name field is a special case - essentially a compound but only ever represented on one line in the spreadsheet
#	Name fields can only appear as components of a compound field (either at eprint or document level)
#	(since really name fields are a TYPE of field not a data field in their own right)
#	If documents.path appears in data schema, it MUST be defined as a multiple field or an error will occur

# TO DO
# clean up to make data hash construction more generic


use strict;
use warnings;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use Getopt::Long;
use File::Basename;



###### CONFIGURATION ######
my %config = (
	# version number
	version => '1.26',
	
	# number of human-readable header rows to ignore before we expect the row of field names
	num_header_rows => 1,
	
	# mandatory fields in the first columns of each worksheet
	prefields => [ 'eprintid', 'rowid', 'documents.docid', 'documents.rowid'],
	
	# check all field names against schema hash
	# even when this is 0, fields are checked against schema for multiplicity
	check_fields => 1,
	
	# allow unordered rows - NOT IMPLEMENTED YET
	allow_unordered => 0,
	
	# warning flags
	warn => {
		# multiple values in non-multiple field
		nonmulti => 0,

		# eprint level data in document level row
		e_in_d_type => 0,
	
		# eprint level data in document level row
		d_in_e_type => 0,
	},
	
	# should we be verbose (noise level can be 0, 1, 2)
	noise => 0,
	
	# column and row index of top left cell in a worksheet (must be 0 or 1 !!)
	# this is dependent on the parser being used
	topleft => {
		col => 0,
		row => 0,
	},
	
	# default eprint-level fields and their default values which are required to be present in each eprint
	# these values will be injected into XML stream unless explicitly defined in the spreadsheet data
	# or redefined on the command line via the appropriate command line options
	dfields => {
		userid => 1,
		eprint_status => 'buffer',
	},
	
	# string used as the row key identifier in compound field hashes
	comprowkey => '__row',
	
	# document path parameters
	docpath => {
		# name of the ("documents.") field containing the full path to the file
		field => 'path',
		# any prefix to be added to document path (can be set at runtime using option "p")
		prefix => '',
	},
	
	# allow overwriting of output file
	overwrite => 0,
	
	# "name" sub-object prefix (note - its sub-fields are NOT classed as multi-fields)
	# note this will be followed by a caret character in spreadsheet field names
	namefieldprefix => 'name',
);

###### INITIALISATIONS ######

# hash of data records to be parsed and written out
# each key corresponds to an eprintid (which is also included internally as one of the fields)
# each key value contains an anonymous hash representing the fields within an eprint
# the anonymous hash keys are the eprint field names
# for multi fields the anonymous hash key values are anonymous arrays which contain field values as elements
# for non-multi fields the anonymous hash key values are the field values
# for compound fields the field values are represented by anonymous hashes (as array elements for multi fields)
# the compound field anonymous hash keys are the sub-field names, the anonymous hash key values are the sub-field values
my %eprints;

# mime-type hash for auto-detection of document mime-types if this field is not present in spreadsheet
my %mimetype;

# document-type hash for auto-detection of document (descriptive) format types if this field is not present in spreadsheet
my %doctype;

# array representing the fields (in order) presented in the spreadsheet
my @efields = ();

# stores name of schema to be used
my $schemaname;

# input file name
my $ipfile;

# output file name
my $opfile;

# global counters
my %count = (
	worksheet => 0,
	row => 0,
	column => 0,
);

# last reference buffer
my %last = (
	eprintid => -1,
	eprint_rowid => -1,
	docid => -1,
	doc_rowid => -1,
);

# indent counter in XML string
my $indent = 0;

# command line options hash
my %opt;

###### DATA SCHEMA DEFINITIONS ######

# all other fields other than the prefields
# value of 'M' means multiple values allowed
my %schema = (
	testtiny => {
		'test' => '',
	},
	testsmall => {
		'epf' => '',
		'epfmulti' => 'M',
		'epfcomp.sub1' => '',
		'epfcomp.sub2' => '',
		'epfcompmulti.sub1' => 'M',
		'epfcompmulti.sub2' => 'M',
		'epfcompname.name^first' => '',
		'epfcompname.name^last' => '',
		'epfcompname.othersub' => '',		
		'epfcompmultiname.name^first' => 'M',
		'epfcompmultiname.name^last' => 'M',
		'epfcompmultiname.othersub' => 'M',
		'documents.main' => '',
		'documents.path' => 'M',
		'documents.docf' => '',
		'documents.docfmulti' => 'M',
		'documents.docfcomp.sub1' => '',
		'documents.docfcomp.sub2' => '',
		'documents.docfcompmulti.sub1' => 'M',
		'documents.docfcompmulti.sub2' => 'M',
		'documents.docfcompname.name^first' => '',
		'documents.docfcompname.name^last' => '',
		'documents.docfcompname.othersub' => '',		
		'documents.docfcompmultiname.name^first' => 'M',
		'documents.docfcompmultiname.name^last' => 'M',
		'documents.docfcompmultiname.othersub' => 'M',

	},
	
	testlarge => {
		'creators.name^family' => 'M',
		'creators.name^first' => 'M',
		'creators.id' => 'M',
		'creators.orcid' => 'M',
		'contributors.type' => 'M',
		'contributors.name^family' => 'M',
		'contributors.name^first' => 'M',
		'contributors.id' => 'M',
		'contributors.orcid' => 'M',
		'corp_creators' => 'M',
		'title' => '',
		'subjects' => 'M',
		'divisions' => 'M',
		'keywords' => '',
		'note' => '',
		'abstract' => '',
		'date.type' => '',
		'date.date' => '',
		'id_number' => '',
		'funders' => 'M',
		'projects' => 'M',
		'output_media' => '',
		'data_type' => '',
		'copyright_holders' => 'M',
		'bounding_box.type' => 'M',
		'bounding_box.north_edge' => 'M',
		'bounding_box.east_edge' => 'M',
		'bounding_box.south_edge' => 'M',
		'bounding_box.west_edge' => 'M',
		'alt_title' => '',
		'collection_method' => '',
		'grant' => 'M',
		'provenance' => '',
		'restrictions' => '',
		'geographic_cover' => 'M',
		'language' => '',
		'legal_ethical' => '',
		'terms_conditions_agreement' => '',
		'collection_date.from' => 'M',
		'collection_date.to' => 'M',
		'temporal_cover' => 'M',
		'related_resources.type' => 'M',
		'related_resources.url' => 'M',
		'doi' => '',
		'alt_identifier' => '',
		'citation' => '',
		'contact' => '',
		
		
		'ispublished' => '',
		'full_text_status' => '',
		'monograph_type' => '',
		'pres_type' => '',
		'suggestions' => '',
		'series' => '',
		'publication' => '',
		'volume' => '',
		'number' => '',
		'publisher' => '',
		'place_of_pub' => '',
		'pagerange' => '',
		'pages' => '',
		'event_title' => '',
		'event_location' => '',
		'event_dates' => '',
		'event_type' => '',
		'patent_applicant' => '',
		'institution' => '',
		'department' => '',
		'thesis_type' => '',
		'refereed' => '',
		'isbn' => '',
		'issn' => '',
		'book_title' => '',
		'editors' => '',
		'official_url' => '',
		'related_url' => '',
		'referencetext' => '',
		'exhibitors' => '',
		'num_pieces' => '',
		'composition_type' => '',
		'producers' => '',
		'conductors' => '',
		'lyricists' => '',
		'accompaniment' => '',
		'pedagogic_type' => '',
		'completion_time' => '',
		'task_purpose' => '',
		'skill_areas' => '',
		'learning_level' => '',
		'gscholar' => '',
		'original_publisher' => '',
	},
	
	researchdata_old => {
		'creators.name^family' => 'M',
		'creators.name^given' => 'M',
		'creators.id' => 'M',
		'creators.orcid' => 'M',
		'contributors.type' => 'M',
		'contributors.name^family' => 'M',
		'contributors.name^given' => 'M',
		'contributors.id' => 'M',
		'contributors.orcid' => 'M',
		'corp_creators' => 'M',
		'title' => '',
		'subjects' => 'M',
		'divisions' => 'M',
		'keywords' => '',
		'note' => '',
		'abstract' => '',
		'date.type' => '',
		'date.date' => '',
		'id_number' => '',
		'funders' => 'M',
		'projects' => 'M',
		'output_media' => '',
		'data_type' => '',
		'copyright_holders' => 'M',
		'bounding_box.type' => 'M',
		'bounding_box.north_edge' => 'M',
		'bounding_box.east_edge' => 'M',
		'bounding_box.south_edge' => 'M',
		'bounding_box.west_edge' => 'M',
		'alt_title' => '',
		'collection_method' => '',
		'grant' => 'M',
		'provenance' => '',
		'restrictions' => '',
		'geographic_cover' => 'M',
		'language' => '',
		'legal_ethical' => '',
		'terms_conditions_agreement' => '',
		'collection_date.date_from' => 'M',
		'collection_date.date_to' => 'M',
		'temporal_cover' => 'M',
		'related_resources.type' => 'M',
		'related_resources.url' => 'M',
		'doi' => '',
		'alt_identifier' => '',
		'citation' => '',
		'contact' => '',
		'documents.main' => '',
		'documents.path' => 'M',
		'collection' => '',
		'subcollection' => '',
		'documents.mime_type' => '',
		'documents.formatdesc' => '',
		'documents.content' => '',
		'documents.date_embargo' => '',
		'documents.rev_number' => '',
		'documents.security' => '',
		'documents.license' => '',

	},
	
	researchdata => {
		'title' => '',
		'id_number' => '',
		'doi' => '',
		'alt_identifier' => 'M',
		'abstract' => '',
		'keywords' => '',
		'subjects' => 'M',
		'divisions' => 'M',
		'version' => '',
		'alt_title' => '',
		'creators.id' => 'M',
		'creators.email' => 'M',
		'creators.other_id' => 'M',
		'creators.name^family' => 'M',
		'creators.name^given' => 'M',
		'corp_creators' => 'M',
		'data_type' => '',
		'contributors.id' => 'M',
		'contributors.email' => 'M',
		'contributors.other_id' => 'M',
		'contributors.name^family' => 'M',
		'contributors.name^given' => 'M',
		'contributors.type' => 'M',
		'funders' => 'M',
		'grant' => 'M',
		'projects' => 'M',
		'collection_date.from' => 'M',
		'collection_date.to' => 'M',
		'temporal_cover.from' => 'M',
		'temporal_cover.to' => 'M',
		'geographic_cover' => 'M',
		'bounding_box.east_edge' => 'M',
		'bounding_box.north_edge' => 'M',
		'bounding_box.south_edge' => 'M',
		'bounding_box.west_edge' => 'M',
		'collection_method' => '',
		'legal_ethical' => '',
		'provenance' => '',
		'language' => 'M',
		'note' => '',
		'related_resources.location' => 'M',
		'related_resources.type' => 'M',
		'copyright_holders' => 'M',
		'date' => '',
		'publisher' => '',
		'contact_email' => '',
		'contact' => '',
		'suggestions' => '',
		'metadata_language' => '',
		'terms_conditions_agreement' => '',
		'citation' => '',
		'license' => '',
		'data_location' => '',
		'restrictions' => '',
		'retention_date' => '',
		'retention_action' => '',
		'retention_comment' => '',
		'collection.name' => '',
		'collection.id' => '',
		'collection.subcollection' => '',
		'record_type' => '',
		'documents.title' => '',
		'documents.version' => '',
		'documents.publication_date' => '',
		'documents.mime_type' => '',
		'documents.formatdesc' => '',
		'documents.content' => '',
		'documents.date_embargo' => '',
		'documents.security' => '',
		'documents.license' => '',
		'documents.doi' => '',
		'documents.note' => '',
		'documents.main' => '',
		'documents.path' => 'M',
	},
	
	timescapes => {
		'tsmd__project' => '',
		'tsmd__fieldworkerID' => '',
		'tsmd__gender' => '',
		'tsmd__caseID' => '',
		'tsmd__ageGroup' => '',
		'tsmd__yearOfBirth' => '',
		'tsmd__ethnicity' => '',
		'tsmd__dataType.type' => '',
		'tsmd__dataType.value' => '',
		'tsmd__employment' => '',
		'tsmd__relationshipStatus' => '',
		'tsmd__location' => '',
		'tsmd__fieldworkDate' => '',
		'tsmd__title' => '',
		'tsmd__description' => '',
		'tsmd__subject' => '',
		'tsmd__caseref' => '',
		'tsmd__waveref' => '',
		'documents.tsmd__project' => '',
		'documents.tsmd__fieldworkerID' => '',
		'documents.tsmd__gender' => '',
		'documents.tsmd__caseID' => '',
		'documents.tsmd__ageGroup' => '',
		'documents.tsmd__yearOfBirth' => '',
		'documents.tsmd__ethnicity' => '',
		'documents.tsmd__dataType.type' => '',
		'documents.tsmd__dataType.value' => '',
		'documents.tsmd__employment' => '',
		'documents.tsmd__relationshipStatus' => '',
		'documents.tsmd__location' => '',
		'documents.tsmd__fieldworkDate' => '',
		'documents.tsmd__title' => '',
		'documents.tsmd__description' => '',
		'documents.tsmd__subject' => '',
		'documents.tsmd__caseref' => '',
		'documents.tsmd__waveref' => '',
		'documents.main' => '',
		'documents.path' => 'M',
		'documents.security' => '',
	}
);


###### MIME-TYPE DEFINITIONS ######
sub init_mimetype {
	%mimetype = (
		'1' => 'application/x-troff-man',
		'123' => 'application/vnd.lotus-1-2-3',
		'2' => 'application/x-troff-man',
		'3' => 'application/x-troff-man',
		'323' => 'text/h323',
		'3dm' => 'text/vnd.in3d.3dml',
		'3dml' => 'text/vnd.in3d.3dml',
		'3g2' => 'video/3gpp2',
		'3gp' => 'video/3gpp',
		'3gpp' => 'video/3gpp',
		'3gpp2' => 'video/3gpp2',
		'4' => 'application/x-troff-man',
		'5' => 'application/x-troff-man',
		'6' => 'application/x-troff-man',
		'669' => 'audio/x-mod',
		'7' => 'application/x-troff-man',
		'726' => 'audio/32kadpcm',
		'8' => 'application/x-troff-man',
		'aa3' => 'audio/ATRAC3',
		'aal' => 'audio/ATRAC-ADVANCED-LOSSLESS',
		'abc' => 'text/vnd.abc',
		'ac' => 'application/vnd.nokia.n-gage.ac+xml',
		'ac3' => 'audio/ac3',
		'acc' => 'application/vnd.americandynamics.acc',
		'acu' => 'application/vnd.acucobol',
		'acutc' => 'application/vnd.acucorp',
		'acx' => 'application/internet-property-stream',
		'aep' => 'application/vnd.audiograph',
		'afp' => 'application/vnd.ibm.modcap',
		'ai' => 'application/postscript',
		'aif' => 'audio/x-aiff',
		'aifc' => 'audio/x-aiff',
		'aiff' => 'audio/x-aiff',
		'ami' => 'application/vnd.amiga.ami',
		'amr' => 'audio/AMR',
		'apr' => 'application/vnd.lotus-approach',
		'apxml' => 'application/auth-policy+xml',
		'art' => 'message/rfc822',
		'asc' => 'text/plain',
		'asf' => 'application/vnd.ms-asf',
		'aso' => 'application/vnd.accpac.simply.aso',
		'asr' => 'video/x-ms-asf',
		'asx' => 'video/x-ms-asf',
		'at3' => 'audio/ATRAC3',
		'atc' => 'application/vnd.acucorp',
		'atom' => 'application/atom+xml',
		'atomcat' => 'application/atomcat+xml',
		'atomsvc' => 'application/atomsvc+xml',
		'atx' => 'audio/ATRAC-X',
		'au' => 'audio/basic',
		'avi' => 'video/x-msvideo',
		'awb' => 'audio/AMR-WB',
		'axs' => 'application/olescript',
		'azf' => 'application/vnd.airzip.filesecure.azf',
		'azs' => 'application/vnd.airzip.filesecure.azs',
		'bar' => 'application/vnd.qualcomm.brew-app-res',
		'bas' => 'text/plain',
		'bcpio' => 'application/x-bcpio',
		'bdm' => 'application/vnd.syncml.dm+wbxml',
		'bed' => 'application/vnd.realvnc.bed',
		'bh2' => 'application/vnd.fujitsu.oasysprs',
		'bin' => 'application/octet-stream',
		'bkm' => 'application/vnd.nervana',
		'bmi' => 'application/vnd.bmi',
		'bmp' => 'image/bmp',
		'box' => 'application/vnd.previewsystems.box',
		'bpd' => 'application/vnd.hbci',
		'btf' => 'image/prs.btif',
		'btif' => 'image/prs.btif',
		'bz2' => 'application/x-bzip2',
		'c' => 'text/plain',
		'c4d' => 'application/vnd.clonk.c4group',
		'c4f' => 'application/vnd.clonk.c4group',
		'c4g' => 'application/vnd.clonk.c4group',
		'c4p' => 'application/vnd.clonk.c4group',
		'c4u' => 'application/vnd.clonk.c4group',
		'cab' => 'application/vnd.ms-cab-compressed',
		'cat' => 'application/vnd.ms-pkiseccat',
		'cc' => 'text/plain',
		'ccc' => 'text/vnd.net2phone.commcenter.command',
		'ccxml' => 'application/ccxml+xml',
		'cdbcmsg' => 'application/vnd.contact.cmsg',
		'cdf' => 'application/x-netcdf',
		'cdkey' => 'application/vnd.mediastation.cdkey',
		'cdxml' => 'application/vnd.chemdraw+xml',
		'cdy' => 'application/vnd.cinderella',
		'cellml' => 'application/cellml+xml',
		'cer' => 'application/pkix-cert',
		'chm' => 'application/vnd.ms-htmlhelp',
		'chrt' => 'application/vnd.kde.kchart',
		'cif' => 'application/vnd.multiad.creator.cif',
		'cii' => 'application/vnd.anser-web-certificate-issue-initiation',
		'cil' => 'application/vnd.ms-artgalry',
		'cl' => 'application/simple-filter+xml',
		'cla' => 'application/vnd.claymore',
		'class' => 'application/octet-stream',
		'clkk' => 'application/vnd.crick.clicker.keyboard',
		'clkp' => 'application/vnd.crick.clicker.palette',
		'clkt' => 'application/vnd.crick.clicker.template',
		'clkw' => 'application/vnd.crick.clicker.wordbank',
		'clkx' => 'application/vnd.crick.clicker',
		'clp' => 'application/x-msclip',
		'cmc' => 'application/vnd.cosmocaller',
		'cml' => 'application/cellml+xml',
		'cmp' => 'application/vnd.yellowriver-custom-menu',
		'cmx' => 'image/x-cmx',
		'cod' => 'image/cis-cod',
		'cpio' => 'application/x-cpio',
		'cpkg' => 'application/vnd.xmpie.cpkg',
		'cpl' => 'application/cpl+xml',
		'cpt' => 'application/mac-compactpro',
		'crd' => 'application/x-mscardfile',
		'crl' => 'application/pkix-crl',
		'crt' => 'application/x-x509-ca-cert',
		'crtr' => 'application/vnd.multiad.creator',
		'csh' => 'application/x-csh',
		'csp' => 'application/vnd.commonspace',
		'css' => 'text/css',
		'cst' => 'application/vnd.commonspace',
		'csv' => 'text/csv',
		'curl' => 'application/vnd.curl',
		'cw' => 'application/prs.cww',
		'cww' => 'application/prs.cww',
		'cxx' => 'text/plain',
		'daf' => 'application/vnd.Mobius.DAF',
		'dataless' => 'application/vnd.fsdn.seed',
		'davmount' => 'application/davmount+xml',
		'dcf' => 'application/vnd.oma.drm.content',
		'dcm' => 'application/dicom',
		'dcr' => 'application/x-director',
		'dd' => 'application/vnd.oma.dd+xml',
		'dd2' => 'application/vnd.oma.dd2+xml',
		'ddd' => 'application/vnd.fujixerox.ddd',
		'der' => 'application/x-x509-ca-cert',
		'dfac' => 'application/vnd.dreamfactory',
		'dir' => 'application/x-director',
		'dis' => 'application/vnd.Mobius.DIS',
		'dist' => 'application/vnd.apple.installer+xml',
		'distz' => 'application/vnd.apple.installer+xml',
		'djv' => 'image/vnd.djvu',
		'djvu' => 'image/vnd.djvu',
		'dll' => 'application/octet-stream',
		'dls' => 'audio/dls',
		'dm' => 'application/vnd.oma.drm.message',
		'dms' => 'text/vnd.DMClientScript',
		'dna' => 'application/vnd.dna',
		'doc' => 'application/msword',
		'docm' => 'application/vnd.ms-word.document.macroEnabled.12',
		'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
		'dor' => 'model/vnd.gdl',
		'dot' => 'text/vnd.graphviz',
		'dotm' => 'application/vnd.ms-word.template.macroEnabled.12',
		'dotx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.template',
		'dp' => 'application/vnd.osgi.dp',
		'dpg' => 'application/vnd.dpgraph',
		'dpgraph' => 'application/vnd.dpgraph',
		'dpkg' => 'application/vnd.xmpie.dpkg',
		'dr' => 'application/vnd.oma.drm.rights+xml',
		'drc' => 'application/vnd.oma.drm.rights+wbxml',
		'dsc' => 'text/prs.lines.tag',
		'dssc' => 'application/dssc+der',
		'dtd' => 'application/xml-dtd',
		'dts' => 'audio/vnd.dts',
		'dtshd' => 'audio/vnd.dts.hd',
		'dvc' => 'application/dvcs',
		'dvi' => 'application/x-dvi',
		'dwf' => 'model/vnd.dwf',
		'dxf' => 'image/vnd.dxf',
		'dxp' => 'application/vnd.spotfire.dxp',
		'dxr' => 'application/x-director',
		'ecelp4800' => 'audio/vnd.nuera.ecelp4800',
		'ecelp7470' => 'audio/vnd.nuera.ecelp7470',
		'ecelp9600' => 'audio/vnd.nuera.ecelp9600',
		'edm' => 'application/vnd.novadigm.EDM',
		'edx' => 'application/vnd.novadigm.EDX',
		'efif' => 'application/vnd.picsel',
		'ei6' => 'application/vnd.pg.osasli',
		'el' => 'text/plain',
		'eml' => 'message/rfc822',
		'emm' => 'application/vnd.ibm.electronic-media',
		'emma' => 'application/emma+xml',
		'ent' => 'text/xml-external-parsed-entity',
		'entity' => 'application/vnd.nervana',
		'eol' => 'audio/vnd.digital-winds',
		'eot' => 'application/vnd.ms-fontobject',
		'ep' => 'application/vnd.bluetooth.ep.oob',
		'eps' => 'application/postscript',
		'es3' => 'application/vnd.eszigno3+xml',
		'esf' => 'application/vnd.epson.esf',
		'et3' => 'application/vnd.eszigno3+xml',
		'etx' => 'text/x-setext',
		'evb' => 'audio/EVRCB',
		'evc' => 'audio/EVRC',
		'evw' => 'audio/EVRCWB',
		'evy' => 'application/envoy',
		'exe' => 'application/octet-stream',
		'ext' => 'application/vnd.novadigm.EXT',
		'ez' => 'application/andrew-inset',
		'ez2' => 'application/vnd.ezpix-album',
		'ez3' => 'application/vnd.ezpix-package',
		'f90' => 'text/plain',
		'fbs' => 'image/vnd.fastbidsheet',
		'fdf' => 'application/vnd.fdf',
		'fe_launch' => 'application/vnd.denovo.fcselayout-link',
		'fg5' => 'application/vnd.fujitsu.oasysgp',
		'fif' => 'application/fractals',
		'finf' => 'application/fastinfoset',
		'fit' => 'image/fits',
		'fits' => 'image/fits',
		'flo' => 'application/vnd.micrografx.flo',
		'flr' => 'x-world/x-vrml',
		'flv' => 'video/x-flv',
		'flw' => 'application/vnd.kde.kivio',
		'flx' => 'text/vnd.fmi.flexstor',
		'fly' => 'text/vnd.fly',
		'fm' => 'application/vnd.framemaker',
		'fnc' => 'application/vnd.frogans.fnc',
		'fo' => 'application/vnd.software602.filler.form+xml',
		'fpx' => 'image/vnd.fpx',
		'frm' => 'application/vnd.ufdl',
		'fsc' => 'application/vnd.fsc.weblaunch',
		'fst' => 'image/vnd.fst',
		'ftc' => 'application/vnd.fluxtime.clip',
		'fti' => 'application/vnd.anser-web-funds-transfer-initiation',
		'fts' => 'image/fits',
		'fvt' => 'video/vnd.fvt',
		'fzs' => 'application/vnd.fuzzysheet',
		'g2w' => 'application/vnd.geoplan',
		'g3w' => 'application/vnd.geospace',
		'gac' => 'application/vnd.groove-account',
		'gdl' => 'model/vnd.gdl',
		'geo' => 'application/vnd.dynageo',
		'gex' => 'application/vnd.geometry-explorer',
		'ggb' => 'application/vnd.geogebra.file',
		'ggt' => 'application/vnd.geogebra.tool',
		'ghf' => 'application/vnd.groove-help',
		'gif' => 'image/gif',
		'gim' => 'application/vnd.groove-identity-message',
		'gph' => 'application/vnd.FloGraphIt',
		'gqf' => 'application/vnd.grafeq',
		'gqs' => 'application/vnd.grafeq',
		'gram' => 'application/srgs',
		'gre' => 'application/vnd.geometry-explorer',
		'grv' => 'application/vnd.groove-injector',
		'grxml' => 'application/srgs+xml',
		'gsm' => 'model/vnd.gdl',
		'gtar' => 'application/x-gtar',
		'gtm' => 'application/vnd.groove-tool-message',
		'gtw' => 'model/vnd.gtw',
		'gv' => 'text/vnd.graphviz',
		'gxt' => 'application/vnd.geonext',
		'gz' => 'application/x-gzip',
		'h' => 'text/plain',
		'hbc' => 'application/vnd.hbci',
		'hbci' => 'application/vnd.hbci',
		'hdf' => 'application/x-hdf',
		'hdr' => 'image/vnd.radiance',
		'hh' => 'text/plain',
		'hlp' => 'application/winhlp',
		'hpgl' => 'application/vnd.hp-HPGL',
		'hpi' => 'application/vnd.hp-hpid',
		'hpid' => 'application/vnd.hp-hpid',
		'hps' => 'application/vnd.hp-hps',
		'hqx' => 'application/mac-binhex40',
		'hta' => 'application/hta',
		'htc' => 'text/x-component',
		'htke' => 'application/vnd.kenameaapp',
		'htm' => 'text/html',
		'html' => 'text/html',
		'htt' => 'text/webviewhtml',
		'hvd' => 'application/vnd.yamaha.hv-dic',
		'hvp' => 'application/vnd.yamaha.hv-voice',
		'hvs' => 'application/vnd.yamaha.hv-script',
		'hxx' => 'text/plain',
		'ic0' => 'application/vnd.commerce-battelle',
		'ic1' => 'application/vnd.commerce-battelle',
		'ic2' => 'application/vnd.commerce-battelle',
		'ic3' => 'application/vnd.commerce-battelle',
		'ic4' => 'application/vnd.commerce-battelle',
		'ic5' => 'application/vnd.commerce-battelle',
		'ic6' => 'application/vnd.commerce-battelle',
		'ic7' => 'application/vnd.commerce-battelle',
		'ic8' => 'application/vnd.commerce-battelle',
		'ica' => 'application/vnd.commerce-battelle',
		'icc' => 'application/vnd.iccprofile',
		'icd' => 'application/vnd.commerce-battelle',
		'ice' => 'x-conference/x-cooltalk',
		'icf' => 'application/vnd.commerce-battelle',
		'icm' => 'application/vnd.iccprofile',
		'ico' => 'image/vnd.microsoft.icon',
		'ics' => 'text/calendar',
		'ief' => 'image/ief',
		'ifb' => 'text/calendar',
		'ifm' => 'application/vnd.shana.informed.formdata',
		'iges' => 'model/iges',
		'igl' => 'application/vnd.igloader',
		'igs' => 'model/iges',
		'igx' => 'application/vnd.micrografx.igx',
		'iif' => 'application/vnd.shana.informed.interchange',
		'iii' => 'application/x-iphone',
		'img' => 'application/octet-stream',
		'imp' => 'application/vnd.accpac.simply.imp',
		'ims' => 'application/vnd.ms-ims',
		'ins' => 'application/x-internet-signup',
		'ipfix' => 'application/ipfix',
		'ipk' => 'application/vnd.shana.informed.package',
		'irm' => 'application/vnd.ibm.rights-management',
		'irp' => 'application/vnd.irepository.package+xml',
		'ism' => 'model/vnd.gdl',
		'iso' => 'application/octet-stream',
		'isp' => 'application/x-internet-signup',
		'itp' => 'application/vnd.shana.informed.formtemplate',
		'ivp' => 'application/vnd.immervision-ivp',
		'ivu' => 'application/vnd.immervision-ivu',
		'jad' => 'text/vnd.sun.j2me.app-descriptor',
		'jam' => 'application/vnd.jam',
		'jar' => 'application/x-java-archive',
		'jfif' => 'image/jpeg',
		'jisp' => 'application/vnd.jisp',
		'jlt' => 'application/vnd.hp-jlyt',
		'jnlp' => 'application/x-java-jnlp-file',
		'joda' => 'application/vnd.joost.joda-archive',
		'jp2' => 'image/jp2',
		'jpe' => 'image/jpeg',
		'jpeg' => 'image/jpeg',
		'jpf' => 'image/jpx',
		'jpg' => 'image/jpeg',
		'jpg2' => 'image/jp2',
		'jpgm' => 'image/jpm',
		'jpm' => 'image/jpm',
		'jpx' => 'image/jpx',
		'js' => 'text/javascript',
		'json' => 'application/json',
		'jtd' => 'text/vnd.esmertec.theme-descriptor',
		'kar' => 'audio/midi',
		'karbon' => 'application/vnd.kde.karbon',
		'kcm' => 'application/vnd.nervana',
		'kfo' => 'application/vnd.kde.kformula',
		'kia' => 'application/vnd.kidspiration',
		'kil' => 'application/x-killustrator',
		'kml' => 'application/vnd.google-earth.kml+xml',
		'kmz' => 'application/vnd.google-earth.kmz',
		'kne' => 'application/vnd.Kinar',
		'knp' => 'application/vnd.Kinar',
		'kom' => 'application/vnd.hbci',
		'kon' => 'application/vnd.kde.kontour',
		'koz' => 'audio/vnd.audikoz',
		'kpr' => 'application/vnd.kde.kpresenter',
		'kpt' => 'application/vnd.kde.kpresenter',
		'ksp' => 'application/vnd.kde.kspread',
		'ktr' => 'application/vnd.kahootz',
		'ktz' => 'application/vnd.kahootz',
		'kwd' => 'application/vnd.kde.kword',
		'kwt' => 'application/vnd.kde.kword',
		'l16' => 'audio/L16',
		'latex' => 'application/x-latex',
		'lbc' => 'audio/iLBC',
		'lbd' => 'application/vnd.llamagraphics.life-balance.desktop',
		'lbe' => 'application/vnd.llamagraphics.life-balance.exchange+xml',
		'les' => 'application/vnd.hhe.lesson-player',
		'lha' => 'application/octet-stream',
		'link66' => 'application/vnd.route66.link66+xml',
		'list3820' => 'application/vnd.ibm.modcap',
		'listafp' => 'application/vnd.ibm.modcap',
		'lmp' => 'model/vnd.gdl',
		'lostxml' => 'application/lost+xml',
		'lrm' => 'application/vnd.ms-lrm',
		'lsf' => 'video/x-la-asf',
		'lsx' => 'video/x-la-asf',
		'ltf' => 'application/vnd.frogans.ltf',
		'lvp' => 'audio/vnd.lucent.voice',
		'lwp' => 'application/vnd.lotus-wordpro',
		'lzh' => 'application/octet-stream',
		'm' => 'application/vnd.wolfram.mathematica.package',
		'm13' => 'application/x-msmediaview',
		'm14' => 'application/x-msmediaview',
		'm15' => 'audio/x-mod',
		'm21' => 'application/mp21',
		'm3u' => 'audio/x-mpegurl',
		'm3u8' => 'application/vnd.apple.mpegurl',
		'm4u' => 'video/vnd.mpegurl',
		'ma' => 'application/mathematica',
		'mag' => 'application/vnd.ecowin.chart',
		'mail' => 'message/rfc822',
		'man' => 'application/x-troff-man',
		'manifest' => 'text/cache-manifest',
		'mb' => 'application/mathematica',
		'mbk' => 'application/vnd.Mobius.MBK',
		'mbox' => 'application/mbox',
		'mc1' => 'application/vnd.medcalcdata',
		'mcd' => 'application/vnd.mcd',
		'mdb' => 'application/x-msaccess',
		'mdc' => 'application/vnd.marlin.drm.mdcf',
		'mdi' => 'image/vnd.ms-modi',
		'me' => 'application/x-troff-me',
		'med' => 'audio/x-mod',
		'mesh' => 'model/mesh',
		'metalink' => 'application/metalink+xml',
		'mfm' => 'application/vnd.mfmp',
		'mgz' => 'application/vnd.proteus.magazine',
		'mht' => 'message/rfc822',
		'mhtml' => 'message/rfc822',
		'mid' => 'audio/midi',
		'midi' => 'audio/midi',
		'mif' => 'application/vnd.mif',
		'mj2' => 'video/mj2',
		'mjp2' => 'video/mj2',
		'mlp' => 'audio/vnd.dolby.mlp',
		'mmd' => 'application/vnd.chipnuts.karaoke-mmd',
		'mmf' => 'application/vnd.smaf',
		'mml' => 'application/mathml+xml',
		'mmr' => 'image/vnd.fujixerox.edmics-mmr',
		'mms' => 'application/vnd.wap.mms-message',
		'mny' => 'application/x-msmoney',
		'mod' => 'audio/x-mod',
		'model-inter' => 'application/vnd.vd-study',
		'moml' => 'model/vnd.moml+xml',
		'mov' => 'video/quicktime',
		'movie' => 'video/x-sgi-movie',
		'mp1' => 'audio/mpeg',
		'mp2' => 'audio/mpeg',
		'mp21' => 'application/mp21',
		'mp3' => 'audio/mpeg',
		'mp4' => 'video/mp4',
		'mpa' => 'video/mpeg',
		'mpc' => 'application/vnd.mophun.certificate',
		'mpe' => 'video/mpeg',
		'mpeg' => 'video/mpeg',
		'mpf' => 'text/vnd.ms-mediapackage',
		'mpg' => 'video/mpeg',
		'mpg4' => 'video/mp4',
		'mpga' => 'audio/mpeg',
		'mpkg' => 'application/vnd.apple.installer+xml',
		'mpm' => 'application/vnd.blueice.multipass',
		'mpn' => 'application/vnd.mophun.application',
		'mpp' => 'application/vnd.ms-project',
		'mpv2' => 'video/mpeg',
		'mpy' => 'application/vnd.ibm.MiniPay',
		'mqy' => 'application/vnd.Mobius.MQY',
		'mrc' => 'application/marc',
		'ms' => 'application/x-troff-ms',
		'msd' => 'application/vnd.fdsn.mseed',
		'mseed' => 'application/vnd.fdsn.mseed',
		'mseq' => 'application/vnd.mseq',
		'msf' => 'application/vnd.epson.msf',
		'msg' => 'application/vnd.ms-outlook',
		'msh' => 'model/mesh',
		'msl' => 'application/vnd.Mobius.MSL',
		'msm' => 'model/vnd.gdl',
		'msty' => 'application/vnd.muvee.style',
		'mtm' => 'audio/x-mod',
		'mts' => 'model/vnd.mts',
		'mus' => 'application/vnd.musician',
		'mvb' => 'application/x-msmediaview',
		'mwc' => 'application/vnd.dpgraph',
		'mwf' => 'application/vnd.MFER',
		'mxf' => 'application/mxf',
		'mxi' => 'application/vnd.vd-study',
		'mxl' => 'application/vnd.recordare.musicxml',
		'mxmf' => 'audio/mobile-xmf',
		'mxml' => 'application/xv+xml',
		'mxs' => 'application/vnd.triscape.mxs',
		'mxu' => 'video/vnd.mpegurl',
		'n-gage' => 'application/vnd.nokia.n-gage.symbian.install',
		'nb' => 'application/mathematica',
		'nbp' => 'application/vnd.wolfram.player',
		'nc' => 'application/x-netcdf',
		'ndc' => 'application/vnd.osa.netdeploy',
		'ndl' => 'application/vnd.lotus-notes',
		'ngdat' => 'application/vnd.nokia.n-gage.data',
		'nim' => 'video/vnd.nokia.interleaved-multimedia',
		'nlu' => 'application/vnd.neurolanguage.nlu',
		'nml' => 'application/vnd.enliven',
		'nnd' => 'application/vnd.noblenet-directory',
		'nns' => 'application/vnd.noblenet-sealer',
		'nnw' => 'application/vnd.noblenet-web',
		'ns2' => 'application/vnd.lotus-notes',
		'ns3' => 'application/vnd.lotus-notes',
		'ns4' => 'application/vnd.lotus-notes',
		'nsf' => 'application/vnd.lotus-notes',
		'nsg' => 'application/vnd.lotus-notes',
		'nsh' => 'application/vnd.lotus-notes',
		'ntf' => 'application/vnd.lotus-notes',
		'nws' => 'message/rfc822',
		'o4a' => 'application/vnd.oma.drm.dcf',
		'o4v' => 'application/vnd.oma.drm.dcf',
		'oa2' => 'application/vnd.fujitsu.oasys2',
		'oa3' => 'application/vnd.fujitsu.oasys3',
		'oas' => 'application/vnd.fujitsu.oasys',
		'oda' => 'application/oda',
		'odb' => 'application/vnd.oasis.opendocument.database',
		'odc' => 'application/vnd.oasis.opendocument.chart',
		'odf' => 'application/vnd.oasis.opendocument.formula',
		'odg' => 'application/vnd.oasis.opendocument.graphics',
		'odi' => 'application/vnd.oasis.opendocument.image',
		'odm' => 'application/vnd.oasis.opendocument.text-master',
		'odp' => 'application/vnd.oasis.opendocument.presentation',
		'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
		'odt' => 'application/vnd.oasis.opendocument.text',
		'oga' => 'audio/ogg',
		'ogg' => 'audio/ogg',
		'ogv' => 'video/ogg',
		'ogx' => 'application/ogg',
		'omg' => 'audio/ATRAC3',
		'opf' => 'application/oebps-package+xml',
		'oprc' => 'application/vnd.palm',
		'or2' => 'application/vnd.lotus-organizer',
		'or3' => 'application/vnd.lotus-organizer',
		'org' => 'application/vnd.lotus-organizer',
		'orq' => 'application/ocsp-request',
		'ors' => 'application/ocsp-response',
		'osf' => 'application/vnd.yamaha.openscoreformat',
		'otc' => 'application/vnd.oasis.opendocument.chart-template',
		'otf' => 'application/vnd.oasis.opendocument.formula-template',
		'otg' => 'application/vnd.oasis.opendocument.graphics-template',
		'oth' => 'application/vnd.oasis.opendocument.text-web',
		'oti' => 'application/vnd.oasis.opendocument.image-template',
		'otp' => 'application/vnd.oasis.opendocument.presentation-template',
		'ots' => 'application/vnd.oasis.opendocument.spreadsheet-template',
		'ott' => 'application/vnd.oasis.opendocument.text-template',
		'oxt' => 'application/vnd.openofficeorg.extension',
		'p10' => 'application/pkcs10',
		'p12' => 'application/x-pkcs12',
		'p7b' => 'application/x-pkcs7-certificates',
		'p7c' => 'application/pkcs7-mime',
		'p7m' => 'application/pkcs7-mime',
		'p7r' => 'application/x-pkcs7-certreqresp',
		'p7s' => 'application/pkcs7-signature',
		'pack' => 'application/x-java-pack200',
		'package' => 'application/vnd.autopackage',
		'pbd' => 'application/vnd.powerbuilder6',
		'pbm' => 'image/x-portable-bitmap',
		'pcl' => 'application/vnd.hp-PCL',
		'pdb' => 'application/vnd.palm',
		'pdf' => 'application/pdf',
		'pfr' => 'application/font-tdpfr',
		'pfx' => 'application/x-pkcs12',
		'pgb' => 'image/vnd.globalgraphics.pgb',
		'pgm' => 'image/x-portable-graymap',
		'pgn' => 'application/x-chess-pgn',
		'pil' => 'application/vnd.piaccess.application-license',
		'pkd' => 'application/vnd.hbci',
		'pkg' => 'application/vnd.apple.installer+xml',
		'pkipath' => 'application/pkix-pkipath',
		'pko' => 'application/ynd.ms-pkipko',
		'pl' => 'application/x-perl',
		'plb' => 'application/vnd.3gpp.pic-bw-large',
		'plc' => 'application/vnd.Mobius.PLC',
		'plf' => 'application/vnd.pocketlearn',
		'plj' => 'audio/vnd.everad.plj',
		'pls' => 'application/pls+xml',
		'pm' => 'text/plain',
		'pma' => 'application/x-perfmon',
		'pmc' => 'application/x-perfmon',
		'pml' => 'application/vnd.ctc-posml',
		'pmr' => 'application/x-perfmon',
		'pmw' => 'application/x-perfmon',
		'png' => 'image/png',
		'pnm' => 'image/x-portable-anymap',
		'pod' => 'text/x-pod',
		'portpkg' => 'application/vnd.macports.portpkg',
		'pot' => 'application/vnd.ms-powerpoint',
		'potm' => 'application/vnd.ms-powerpoint.template.macroEnabled.12',
		'potx' => 'application/vnd.openxmlformats-officedocument.presentationml.template',
		'ppam' => 'application/vnd.ms-powerpoint.addin.macroEnabled.12',
		'ppd' => 'application/vnd.cups-ppd',
		'ppkg' => 'application/vnd.xmpie.ppkg',
		'ppm' => 'image/x-portable-pixmap',
		'pps' => 'application/vnd.ms-powerpoint',
		'ppsm' => 'application/vnd.ms-powerpoint.slideshow.macroEnabled.12',
		'ppsx' => 'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
		'ppt' => 'application/vnd.ms-powerpoint',
		'pptm' => 'application/vnd.ms-powerpoint.presentation.macroEnabled.12',
		'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
		'pqa' => 'application/vnd.palm',
		'prc' => 'application/vnd.palm',
		'pre' => 'application/vnd.lotus-freelance',
		'preminet' => 'application/vnd.preminet',
		'prf' => 'application/pics-rules',
		'prz' => 'application/vnd.lotus-freelance',
		'ps' => 'application/postscript',
		'psb' => 'application/vnd.3gpp.pic-bw-small',
		'psd' => 'image/vnd.adobe.photoshop',
		'pseg3820' => 'application/vnd.ibm.modcap',
		'psid' => 'audio/prs.sid',
		'pti' => 'image/prs.pti',
		'ptid' => 'application/vnd.pvi.ptid1',
		'pub' => 'application/x-mspublisher',
		'pvb' => 'application/vnd.3gpp.pic-bw-var',
		'pwn' => 'application/vnd.3M.Post-it-Notes',
		'pya' => 'audio/vnd.ms-playready.media.pya',
		'pyv' => 'video/vnd.ms-playready.media.pyv',
		'qam' => 'application/vnd.epson.quickanime',
		'qbo' => 'application/vnd.intu.qbo',
		'qca' => 'application/vnd.ericsson.quickcall',
		'qcall' => 'application/vnd.ericsson.quickcall',
		'qcp' => 'audio/qcelp',
		'qfx' => 'application/vnd.intu.qfx',
		'qps' => 'application/vnd.publishare-delta-tree',
		'qt' => 'video/quicktime',
		'qwd' => 'application/vnd.Quark.QuarkXPress',
		'qwt' => 'application/vnd.Quark.QuarkXPress',
		'qxb' => 'application/vnd.Quark.QuarkXPress',
		'qxd' => 'application/vnd.Quark.QuarkXPress',
		'qxl' => 'application/vnd.Quark.QuarkXPress',
		'qxt' => 'application/vnd.Quark.QuarkXPress',
		'ra' => 'audio/x-realaudio',
		'ram' => 'audio/x-pn-realaudio',
		'ras' => 'image/x-cmu-raster',
		'rcprofile' => 'application/vnd.ipunplugged.rcprofile',
		'rct' => 'application/prs.nprend',
		'rdf' => 'application/rdf+xml',
		'rdz' => 'application/vnd.data-vision.rdz',
		'rep' => 'application/vnd.businessobjects',
		'request' => 'application/vnd.nervana',
		'rgb' => 'image/x-rgb',
		'rgbe' => 'image/vnd.radiance',
		'rif' => 'application/reginfo+xml',
		'rl' => 'application/resource-lists+xml',
		'rlc' => 'image/vnd.fujixerox.edmics-rlc',
		'rld' => 'application/resource-lists-diff+xml',
		'rm' => 'audio/x-pn-realaudio',
		'rmi' => 'audio/mid',
		'rms' => 'application/vnd.jcp.javame.midlet-rms',
		'rnc' => 'application/relax-ng-compact-syntax',
		'rnd' => 'application/prs.nprend',
		'roff' => 'application/x-troff',
		'rp9' => 'application/vnd.cloanto.rp9',
		'rpm' => 'application/x-rpm',
		'rpss' => 'application/vnd.nokia.radio-presets',
		'rpst' => 'application/vnd.nokia.radio-preset',
		'rq' => 'application/sparql-query',
		'rs' => 'application/rls-services+xml',
		'rsm' => 'model/vnd.gdl',
		'rss' => 'application/rss+xml',
		'rst' => 'text/prs.fallenstein.rst',
		'rtf' => 'application/rtf',
		'rtx' => 'text/richtext',
		's11' => 'video/vnd.sealed.mpeg1',
		's14' => 'video/vnd.sealed.mpeg4',
		's1a' => 'application/vnd.sealedmedia.softseal.pdf',
		's1e' => 'application/vnd.sealed.xls',
		's1g' => 'image/vnd.sealedmedia.softseal.gif',
		's1h' => 'application/vnd.sealedmedia.softseal.html',
		's1j' => 'image/vnd.sealedmedia.softseal.jpg',
		's1m' => 'audio/vnd.sealedmedia.softseal.mpeg',
		's1n' => 'image/vnd.sealed.png',
		's1p' => 'application/vnd.sealed.ppt',
		's1q' => 'video/vnd.sealedmedia.softseal.mov',
		's1w' => 'application/vnd.sealed.doc',
		's3df' => 'application/vnd.sealed.3df',
		's3m' => 'audio/x-s3m',
		'saf' => 'application/vnd.yamaha.smaf-audio',
		'sam' => 'application/vnd.lotus-wordpro',
		'sc' => 'application/vnd.ibm.secure-container',
		'scd' => 'application/vnd.scribus',
		'scm' => 'application/vnd.lotus-screencam',
		'scq' => 'application/scvp-cv-request',
		'scs' => 'application/scvp-cv-response',
		'scsf' => 'application/vnd.sealed.csf',
		'sct' => 'text/scriptlet',
		'sdf' => 'application/vnd.Kinar',
		'sdkd' => 'application/vnd.solent.sdkm+xml',
		'sdkm' => 'application/vnd.solent.sdkm+xml',
		'sdo' => 'application/vnd.sealed.doc',
		'sdoc' => 'application/vnd.sealed.doc',
		'sdp' => 'application/sdp',
		'see' => 'application/vnd.seemail',
		'seed' => 'application/vnd.fsdn.seed',
		'sem' => 'application/vnd.sealed.eml',
		'sema' => 'application/vnd.sema',
		'semd' => 'application/vnd.semd',
		'semf' => 'application/vnd.semf',
		'seml' => 'application/vnd.sealed.eml',
		'setpay' => 'application/set-payment-initiation',
		'setreg' => 'application/set-registration-initiation',
		'sfd' => 'application/vnd.font-fontforge-sfd',
		'sfd-hdstx' => 'application/vnd.hydrostatix.sof-data',
		'sfs' => 'application/vnd.spotfire.sfs',
		'sgi' => 'image/vnd.sealedmedia.softseal.gif',
		'sgif' => 'image/vnd.sealedmedia.softseal.gif',
		'sgm' => 'text/sgml',
		'sgml' => 'text/sgml',
		'sh' => 'application/x-sh',
		'shar' => 'application/x-shar',
		'shf' => 'application/shf+xml',
		'si' => 'text/vnd.wap.si',
		'sic' => 'application/vnd.wap.sic',
		'sid' => 'audio/prs.sid',
		'sieve' => 'application/sieve',
		'sig' => 'application/pgp-signature',
		'silo' => 'model/mesh',
		'sis' => 'application/vnd.symbian.install',
		'sisx' => 'x-epoc/x-sisx-app',
		'sit' => 'application/x-stuffit',
		'siv' => 'application/sieve',
		'sjp' => 'image/vnd.sealedmedia.softseal.jpg',
		'sjpg' => 'image/vnd.sealedmedia.softseal.jpg',
		'skd' => 'application/vnd.koan',
		'skm' => 'application/vnd.koan',
		'skp' => 'application/vnd.koan',
		'skt' => 'application/vnd.koan',
		'sl' => 'text/vnd.wap.sl',
		'sla' => 'application/vnd.scribus',
		'slaz' => 'application/vnd.scribus',
		'slc' => 'application/vnd.wap.slc',
		'sldm' => 'application/vnd.ms-powerpoint.slide.macroEnabled.12',
		'sldx' => 'application/vnd.openxmlformats-officedocument.presentationml.slide',
		'slt' => 'application/vnd.epson.salt',
		'smh' => 'application/vnd.sealed.mht',
		'smht' => 'application/vnd.sealed.mht',
		'smi' => 'application/smil',
		'smil' => 'application/smil',
		'sml' => 'application/smil',
		'smo' => 'video/vnd.sealedmedia.softseal.mov',
		'smov' => 'video/vnd.sealedmedia.softseal.mov',
		'smp' => 'audio/vnd.sealedmedia.softseal.mpeg',
		'smp3' => 'audio/vnd.sealedmedia.softseal.mpeg',
		'smpg' => 'video/vnd.sealed.mpeg1',
		'sms' => 'application/vnd.3gpp2.sms',
		'smv' => 'audio/SMV',
		'snd' => 'audio/basic',
		'so' => 'application/octet-stream',
		'soa' => 'text/dns',
		'soc' => 'application/sgml-open-catalog',
		'spc' => 'application/x-pkcs7-certificates',
		'spd' => 'application/vnd.sealedmedia.softseal.pdf',
		'spdf' => 'application/vnd.sealedmedia.softseal.pdf',
		'spf' => 'application/vnd.yamaha.smaf-phrase',
		'spl' => 'application/x-futuresplash',
		'spn' => 'image/vnd.sealed.png',
		'spng' => 'image/vnd.sealed.png',
		'spo' => 'text/vnd.in3d.spot',
		'spot' => 'text/vnd.in3d.spot',
		'spp' => 'application/scvp-vp-response',
		'sppt' => 'application/vnd.sealed.ppt',
		'spq' => 'application/scvp-vp-request',
		'spx' => 'audio/ogg',
		'src' => 'application/x-wais-source',
		'srx' => 'application/sparql-results+xml',
		'sse' => 'application/vnd.kodak-descriptor',
		'ssf' => 'application/vnd.epson.ssf',
		'ssml' => 'application/ssml+xml',
		'sst' => 'application/vnd.ms-pkicertstore',
		'ssw' => 'video/vnd.sealed.swf',
		'sswf' => 'video/vnd.sealed.swf',
		'st' => 'application/vnd.sailingtracker.track',
		'stc' => 'application/vnd.sun.xml.calc.template',
		'std' => 'application/vnd.sun.xml.draw.template',
		'stf' => 'application/vnd.wt.stf',
		'sti' => 'application/vnd.sun.xml.impress.template',
		'stif' => 'application/vnd.sealed.tiff',
		'stk' => 'application/hyperstudio',
		'stl' => 'application/vnd.ms-pkistl',
		'stm' => 'audio/x-stm',
		'stml' => 'application/vnd.sealedmedia.softseal.html',
		'str' => 'application/vnd.pg.format',
		'study-inter' => 'application/vnd.vd-study',
		'stw' => 'application/vnd.sun.xml.writer.template',
		'sus' => 'application/vnd.sus-calendar',
		'susp' => 'application/vnd.sus-calendar',
		'sv4cpio' => 'application/x-sv4cpio',
		'sv4crc' => 'application/x-sv4crc',
		'svg' => 'image/svg+xml',
		'svgz' => 'image/svg+xml',
		'swf' => 'application/x-shockwave-flash',
		'swi' => 'application/vnd.aristanetworks.swi',
		'sxc' => 'application/vnd.sun.xml.calc',
		'sxd' => 'application/vnd.sun.xml.draw',
		'sxg' => 'application/vnd.sun.xml.writer.global',
		'sxi' => 'application/vnd.sun.xml.impress',
		'sxl' => 'application/vnd.sealed.xls',
		'sxls' => 'application/vnd.sealed.xls',
		'sxm' => 'application/vnd.sun.xml.math',
		'sxw' => 'application/vnd.sun.xml.writer',
		't' => 'application/x-troff',
		't38' => 'image/t38',
		'tag' => 'text/prs.lines.tag',
		'tao' => 'application/vnd.tao.intent-module-archive',
		'tar' => 'application/x-tar',
		'tcap' => 'application/vnd.3gpp2.tcap',
		'tcl' => 'application/x-tcl',
		'teacher' => 'application/vnd.smart.teacher',
		'tex' => 'application/x-tex',
		'texi' => 'application/x-texinfo',
		'texinfo' => 'application/x-texinfo',
		'text' => 'text/plain',
		'tfx' => 'image/tiff-fx',
		'tga' => 'image/x-targa',
		'tgz' => 'application/x-gzip',
		'tif' => 'image/tiff',
		'tiff' => 'image/tiff',
		'tlclient' => 'application/vnd.cendio.thinlinc.clientconf',
		'tmo' => 'application/vnd.tmobile-livetv',
		'tnef' => 'application/vnd.ms-tnef',
		'tnf' => 'application/vnd.ms-tnef',
		'torrent' => 'application/x-bittorrent',
		'tpl' => 'application/vnd.groove-tool-template',
		'tpt' => 'application/vnd.trid.tpt',
		'tr' => 'application/x-troff',
		'tra' => 'application/vnd.trueapp',
		'trm' => 'application/x-msterminal',
		'ts' => 'text/vnd.trolltech.linguist',
		'tsq' => 'application/timestamp-query',
		'tsr' => 'application/timestamp-reply',
		'tsv' => 'text/tab-separated-values',
		'twd' => 'application/vnd.SimTech-MindMapper',
		'twds' => 'application/vnd.SimTech-MindMapper',
		'txd' => 'application/vnd.genomatix.tuxedo',
		'txf' => 'application/vnd.Mobius.TXF',
		'txt' => 'text/plain',
		'u8dsn' => 'message/global-delivery-status',
		'u8hdr' => 'message/global-headers',
		'u8mdn' => 'message/global-disposition-notification',
		'u8msg' => 'message/global',
		'ufd' => 'application/vnd.ufdl',
		'ufdl' => 'application/vnd.ufdl',
		'uls' => 'text/iuls',
		'ult' => 'audio/x-mod',
		'umj' => 'application/vnd.umajin',
		'uni' => 'audio/x-mod',
		'unityweb' => 'application/vnd.unity',
		'uo' => 'application/vnd.uoml+xml',
		'uoml' => 'application/vnd.uoml+xml',
		'upa' => 'application/vnd.hbci',
		'uri' => 'text/uri-list',
		'uric' => 'text/vnd.si.uricatalogue',
		'uris' => 'text/uri-list',
		'ustar' => 'application/x-ustar',
		'utz' => 'application/vnd.uiq.theme',
		'vbk' => 'audio/vnd.nortel.vbk',
		'vbox' => 'application/vnd.previewsystems.box',
		'vcd' => 'application/x-cdlink',
		'vcf' => 'text/x-vcard',
		'vcg' => 'application/vnd.groove-vcard',
		'vcx' => 'application/vnd.vcx',
		'vew' => 'application/vnd.lotus-approach',
		'vis' => 'application/vnd.visionary',
		'vpm' => 'multipart/voice-message',
		'vrml' => 'model/vrml',
		'vsc' => 'application/vnd.vidsoft.vidconference',
		'vsd' => 'application/vnd.visio',
		'vsf' => 'application/vnd.vsf',
		'vss' => 'application/vnd.visio',
		'vst' => 'application/vnd.visio',
		'vsw' => 'application/vnd.visio',
		'vtu' => 'model/vnd.vtu',
		'vwx' => 'application/vnd.vectorworks',
		'vxml' => 'application/voicexml+xml',
		'wadl' => 'application/vnd.sun.wadl+xml',
		'wav' => 'audio/x-wav',
		'wax' => 'audio/x-ms-wax',
		'wbmp' => 'image/vnd.wap.wbmp',
		'wbs' => 'application/vnd.criticaltools.wbs+xml',
		'wbxml' => 'application/vnd.wap.wbxml',
		'wcm' => 'application/vnd.ms-works',
		'wdb' => 'application/vnd.ms-works',
		'webm' => 'video/webm',
		'wif' => 'application/watcherinfo+xml',
		'win' => 'model/vnd.gdl',
		'wk1' => 'application/vnd.lotus-1-2-3',
		'wk3' => 'application/vnd.lotus-1-2-3',
		'wk4' => 'application/vnd.lotus-1-2-3',
		'wks' => 'application/vnd.ms-works',
		'wm' => 'video/x-ms-wm',
		'wma' => 'audio/x-ms-wma',
		'wmc' => 'application/vnd.wmc',
		'wmf' => 'application/x-msmetafile',
		'wml' => 'text/vnd.wap.wml',
		'wmlc' => 'application/vnd.wap.wmlc',
		'wmls' => 'text/vnd.wap.wmlscript',
		'wmlsc' => 'application/vnd.wap.wmlscriptc',
		'wmv' => 'video/x-ms-wmv',
		'wmx' => 'video/x-ms-wmx',
		'wpd' => 'application/vnd.wordperfect',
		'wpl' => 'application/vnd.ms-wpl',
		'wps' => 'application/vnd.ms-works',
		'wqd' => 'application/vnd.wqd',
		'wri' => 'application/x-mswrite',
		'wrl' => 'model/vrml',
		'wrz' => 'x-world/x-vrml',
		'wsc' => 'application/vnd.wfa.wsc',
		'wsdl' => 'application/wsdl+xml',
		'wspolicy' => 'application/wspolicy+xml',
		'wtb' => 'application/vnd.webturbo',
		'wv' => 'application/vnd.wv.csp+wbxml',
		'wvx' => 'video/x-ms-wvx',
		'x3d' => 'application/vnd.hzn-3d-crossword',
		'x_b' => 'model/vnd.parasolid.transmit.binary',
		'x_t' => 'model/vnd.parasolid.transmit.text',
		'xaf' => 'x-world/x-vrml',
		'xar' => 'application/vnd.xara',
		'xav' => 'application/xcap-att+xml',
		'xbd' => 'application/vnd.fujixerox.docuworks.binder',
		'xbm' => 'image/x-xbitmap',
		'xca' => 'application/xcap-caps+xml',
		'xdm' => 'application/vnd.syncml.dm+xml',
		'xdp' => 'application/vnd.adobe.xdp+xml',
		'xdssc' => 'application/dssc+xml',
		'xdw' => 'application/vnd.fujixerox.docuworks',
		'xel' => 'application/xcap-el+xml',
		'xer' => 'application/xcap-error+xml',
		'xfd' => 'application/vnd.xfdl',
		'xfdf' => 'application/vnd.adobe.xfdf',
		'xfdl' => 'application/vnd.xfdl',
		'xht' => 'application/xhtml+xml',
		'xhtm' => 'application/xhtml+xml',
		'xhtml' => 'application/xhtml+xml',
		'xhvml' => 'application/xv+xml',
		'xif' => 'image/vnd.xiff',
		'xla' => 'application/vnd.ms-excel',
		'xlam' => 'application/vnd.ms-excel.addin.macroEnabled.12',
		'xlc' => 'application/vnd.ms-excel',
		'xlim' => 'application/vnd.xmpie.xlim',
		'xlm' => 'application/vnd.ms-excel',
		'xls' => 'application/vnd.ms-excel',
		'xlsb' => 'application/vnd.ms-excel.sheet.binary.macroEnabled.12',
		'xlsm' => 'application/vnd.ms-excel.sheet.macroEnabled.12',
		'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
		'xlt' => 'application/vnd.ms-excel',
		'xltm' => 'application/vnd.ms-excel.template.macroEnabled.12',
		'xltx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.template',
		'xlw' => 'application/vnd.ms-excel',
		'xml' => 'text/xml',
		'xmt_bin' => 'model/vnd.parasolid.transmit.binary',
		'xmt_txt' => 'model/vnd.parasolid.transmit.text',
		'xns' => 'application/xcap-ns+xml',
		'xo' => 'application/vnd.olpc-sugar',
		'xof' => 'x-world/x-vrml',
		'xop' => 'application/xop+xml',
		'xpm' => 'image/x-xpixmap',
		'xpr' => 'application/vnd.is-xpr',
		'xps' => 'application/vnd.ms-xpsdocument',
		'xpw' => 'application/vnd.intercon.formnet',
		'xpx' => 'application/vnd.intercon.formnet',
		'xsl' => 'application/xslt+xml',
		'xslt' => 'application/xslt+xml',
		'xsm' => 'application/vnd.syncml+xml',
		'xul' => 'application/vnd.mozilla.xul+xml',
		'xvm' => 'application/xv+xml',
		'xvml' => 'application/xv+xml',
		'xwd' => 'image/x-xwindowdump',
		'xyz' => 'chemical/x-xyz',
		'xyze' => 'image/vnd.radiance',
		'xz' => 'application/x-xz',
		'z' => 'application/x-compress',
		'zaz' => 'application/vnd.zzazz.deck+xml',
		'zfo' => 'application/vnd.software602.filler.form-xml-zip',
		'zip' => 'application/zip',
		'zir' => 'application/vnd.zul',
		'zirz' => 'application/vnd.zul',
		'zmm' => 'application/vnd.HandHeld-Entertainment+xml',
		'zone' => 'text/dns',
	);

}


###### DOCUMENT-TYPE DEFINITIONS ######
# Defines specific EPrints document types based on extension.
# If an extension is not defined here, the first part of the mime description will be used instead.
sub init_doctype {
	%doctype = (
		'zip' => 'archive',
		'gz' => 'archive',
		'tgz' => 'archive',
		'ppt' => 'slidehsow',
		'pptx' => 'slideshow',
		'pdf' => 'text',
		'doc' => 'text',
		'docx' => 'text',
		'xls' => 'spreadsheet',
		'xlsx' => 'spreadsheet',
	);
}


###### START MAIN ######
# switch off buffering
$|++;

get_ext_schemas();
get_options();

show_usage() if $#ARGV != 2;

($schemaname, $ipfile, $opfile) = @ARGV;

die "\nERROR: Unknown schema '$schemaname'\n\n" if !defined $schema{$schemaname}; 
die "\nERROR: Cannot find file '$ipfile'\n\n" if ! -f $ipfile;
die "\nERROR: Output file '$opfile' already exists. Use the -o option to allow overwriting.\n\n" if ! $config{overwrite} && -f $opfile;


###### START PARSER DEPENDENT SECTION ######

my $parser   = Spreadsheet::ParseExcel->new();
my $workbook = $parser->parse($ipfile);
die "\nERROR: " . $parser->error() . "\n\n" if ( !defined $workbook );

print "\nTotal number of worksheets: " . scalar($workbook->worksheets()) . "\n";

foreach my $worksheet ( $workbook->worksheets() ) {
	$count{worksheet}++;
	$count{row} = 0;
	$count{column} = 0;
	
	next if $count{worksheet} > 1;
	print "\nOnly processing worksheet number: $count{worksheet}\n\n";
	
	# Find out the worksheet ranges
	my ( $row_min, $row_max ) = $worksheet->row_range();
	my ( $col_min, $col_max ) = $worksheet->col_range();
	
	my $col_count = 1 + $col_max - $col_min;
	my $row_count = 1 + $row_max - $row_min;
	my $datarows = $row_count - $config{num_header_rows} - 1;
	
	die "\nERROR: There are empty columns at the start of the worksheet\n\n" if ($col_min != $config{topleft}{col});
	die "\nERROR: There are empty rows at the start of the worksheet\n\n" if ($row_min != $config{topleft}{row});
	
	print "Ignoring $config{num_header_rows} rows at top of spreadsheet\n" if $config{noise};
	print "There are $datarows rows of data (excluding field name row)\n" if $config{noise};
	
	foreach my $row ( $row_min .. $row_max ) {
		$count{row}++;
		$count{column} = 0;
		
		# ignore "human" header rows
		next if ( ($config{num_header_rows} + $config{topleft}{row}) > $row );
		
		my %cells;
		foreach my $col ( $col_min .. $col_max ) {
			$count{column}++;
			
			# Return the cell object at $row and $col
			my $cell = $worksheet->get_cell( $row, $col );
			$cells{$col-$config{topleft}{col}} = $cell->value() if $cell;
		}
		if (($row-$config{topleft}{row}) == $config{num_header_rows}) {
			die "\nERROR: There are blank cells in the first row of field names\n\n" if (scalar keys %cells != $col_count);
			load_fields(\%cells);
		}
		else {
			add_data(\%cells, $row-$config{topleft}{row});
		}
	}
}

###### END PARSER DEPENDENT SECTION ######

print Dumper(%eprints)."\n" if $config{noise} > 1;

# we are about to run main XML output routine so initialise the doctype and mimetype hashes
init_doctype();
init_mimetype();

write_xml();

###### END MAIN ######




###### SUBROUTINES ######

# loads field names from first row (excluding human readable header rows) of spreadsheet
# NOTE - assumes zero based hash keys
sub load_fields {
	my %hash = %{$_[0]};
	my $i = 0;
	# check mandatory fields are present
	foreach my $field (@{$config{prefields}}) {
		die "\nERROR: Mandatory field \"$field\" not present in column '" . colref($i,0) ."'\n\n" if ($hash{$i} ne $field);
		$i++;
	}
	# reset counter
	$i =0;
	# cycle through fields and load them into efields list as long as they are present in schema hash or are a "prefield"
	foreach my $key (sort {$a <=> $b} keys %hash) {
		if ($config{check_fields}) {
			if ( !is_prefield($hash{$key}) && ! defined $schema{$schemaname}{$hash{$key}}) {
				die "\nERROR: Field '$hash{$key}' not found in data schema\n\n";
			}
		}
		# check for field name duplication
		die "\nERROR: Duplicate field name '$hash{$key}' in column '" . colref($i,0) . "'\n\n" if $hash{$key} ~~ @efields;
		# check for compound field errors e.g. multiple levels of compoundness (is that a word?)
		is_compound($hash{$key});
		
		# check for name fields not within a compound field
		if ( $hash{$key} =~ /^$config{namefieldprefix}\^(.*)/ || $hash{$key} =~ /^documents\.$config{namefieldprefix}\^(.*)/ ) {
			die "\nERROR: Name-type field '$hash{$key}' in column '" . colref($i,0) . "' not a component of a compound field\n\n";
		}
		
		# push onto field name list
		push @efields, $hash{$key};
		$i++;
	}
	print "Total fields: ".scalar(@efields)."\n" if $config{noise}; 
	print "Fields defined in spreadsheet are: -\n" . join "\n", @efields if $config{noise} > 1;
}

# adds data from one row of the spreadsheet
# NOTE - assumes zero based hash keys
sub add_data {
	my %hash = %{$_[0]};
	my $row = $_[1];
	my $rref = rowref($row,0);
	my %eprint;
	my %document;
	my $doclevel = 0; # if 1 data is document level
	my $eprintid;
	my $eprint_rowid;
	my $docid;
	my $doc_rowid;
	my $value;

	########## CURRENTLY BLANK COLUMNS WILL CAUSE INCORRECT FIELD ASSIGNMENTS

	# check that eprintid and rowid are present (we don't do 'defined' - should always evaluate to true)
	die "\nERROR: Mandatory field '$efields[0]' not present on row $rref\n\n" if ! $hash{0};
	die "\nERROR: Mandatory field '$efields[1]' not present on row $rref\n\n" if ! $hash{1};
	
	# check validity of rowid value
	die "\nERROR: Bad format in '$efields[1]' field on row $rref\n\n" if $hash{1} !~ /^[0-9]+_[0-9]+$/;
	($eprintid, $eprint_rowid) = split "_", $hash{1};
	die "\nERROR: Value in '$efields[1]' field is not related to value in '$efields[0]' field on row $rref\n\n" if $hash{0} ne $eprintid;
	if ($eprint_rowid eq '0') {
		# we should be dealing with new eprintid
		die "\nERROR: Bad row index in '$efields[1]' value on row $rref\n\n" if $eprintid eq $last{eprintid};
		die "\nERROR: Duplicate '$efields[0]' on row $rref\n\n" if defined $eprints{$eprintid};
		$last{eprintid} = $eprintid;
		$last{eprint_rowid} = $eprint_rowid;
		$eprints{$eprintid} = { $efields[0] => [ $eprintid ], documents => {} };
	}
	else {
		# we should be dealing with previous eprintid and rowid should be consecutive
		die "\nERROR: Bad row index in '$efields[1]' value on row $rref\n\n" if $eprint_rowid != $last{eprint_rowid} + 1;
		$last{eprint_rowid} = $eprint_rowid;
	}
	
	# check that documents.rowid is present if documents.docid is supplied
	if ( $hash{2} ) {
		die "\nERROR: Mandatory field '$efields[3]' not present on row $rref\n\n" if ! $hash{3};
		# set doclevel flag since we are dealing with doc level data
		$doclevel = 1;
		# check validity of documents.rowid value
		die "\nERROR: Bad format in '$efields[3]' field on row $rref\n\n" if $hash{3} !~ /^[0-9]+_[0-9]+$/;
		($docid, $doc_rowid) = split "_", $hash{3};
		die "\nERROR: Value in '$efields[3]' field is not related to value in '$efields[2]' field on row $rref\n\n" if $hash{2} ne $docid;
		if ($doc_rowid eq '0') {
			# we should be dealing with new docid
			die "\nERROR: Bad row index in '$efields[3]' value on row $rref\n\n" if $docid eq $last{docid} && $eprintid eq $last{doc_eprintid};
			die "\nERROR: Duplicate '$efields[3]' on row $rref\n\n" if defined $eprints{$eprintid}{documents}{$docid};
			$last{docid} = $docid;
			$last{doc_eprintid} = $eprintid;
			$last{doc_rowid} = $doc_rowid;
			$eprints{$eprintid}{documents}{$docid} = {};
		}
		else {
			# we should be dealing with previous docid and rowid should be consecutive
			die "\nERROR: Bad row index in '$efields[3]' value on row $rref\n\n" if $doc_rowid != $last{doc_rowid} + 1;
			$last{doc_rowid} = $doc_rowid;
		}
	}
	my $i = 0;
	
	# BEGIN TRAVERSING THROUGH THE ROW VALUES
	# don't really need to numerically sort the hash keys here but better for user if we do
	foreach my $key (sort {$a <=> $b} keys %hash) {
		my $field = $efields[$key];
		
		# ignore prefields because they have been processed already
		next if is_prefield($field);

		# remove leading, trailing and multiple spaces
		$hash{$key} = xml_safe($hash{$key});

		# ignore if the cell is empty
		next if $hash{$key} eq '';
		
		my $cref = colref($key,0);
		# document level
		if ($doclevel) {
			print "WARNING: ignoring non-empty eprint-level field '$field' (col '$cref') (value = '$hash{$key}') in document-level row (row $rref)\n" if $config{warn}{e_in_d_type} && ($field !~ /^documents\.(.*)/);  
			next if ($field !~ /^documents\.(.*)/);
			# get the document field name
			my $docfield = $1;
			# check for compound field
			my ($compound, $component) = is_compound($field);
			if (defined $compound) {
				# if the compound field is already defined for this eprint document
				if (defined $eprints{$eprintid}{documents}{$docid}{$compound}) {
					# if we have a multi-field
					if (is_multifield($field)) {
						# if the row is the current one we must be adding another sub-field to the compound hash
						if ( $eprints{$eprintid}{documents}{$docid}{$compound}[-1]{$config{comprowkey}} == $row ) {
							# if the field is a name sub-object
							if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
								my $name_subfield = $1;
								# if we already have a name hash use it
								if (defined $eprints{$eprintid}{documents}{$docid}{$compound}[-1]{$config{namefieldprefix}}) {
									$eprints{$eprintid}{documents}{$docid}{$compound}[-1]{$config{namefieldprefix}}{$name_subfield} = $hash{$key};
								}
								# otherwise we need to create a name hash
								else {
									$eprints{$eprintid}{documents}{$docid}{$compound}[-1]{$config{namefieldprefix}} = { $name_subfield => $hash{$key} };
								}
							}
							# not a name sub-object
							else {
								$eprints{$eprintid}{documents}{$docid}{$compound}[-1]{$component} = $hash{$key};
							}
						}
						# otherwise we are creating another compound field hash, so push it onto the array
						else {
							# if the field is a name sub-object
							if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
								my $name_subfield = $1;
								push @{$eprints{$eprintid}{documents}{$docid}{$compound}}, { $config{comprowkey} => $row, $config{namefieldprefix} => { $name_subfield => $hash{$key} } };
							}
							# not a name sub-object
							else {
								push @{$eprints{$eprintid}{documents}{$docid}{$compound}}, { $config{comprowkey} => $row, $component => $hash{$key} };
							}
						}
					}
					
					# not a multi-field
					else {
						# if the compound field is defined for this eprint and the row is the current one
						# we must be adding another sub-field to the compound hash
						if ( $eprints{$eprintid}{documents}{$docid}{$compound}{$config{comprowkey}} == $row ) {
							# if the field is a name sub-object
							if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
								my $name_subfield = $1;
								# if we already have a name hash use it
								if (defined $eprints{$eprintid}{documents}{$docid}{$compound}{$config{namefieldprefix}}) {
									$eprints{$eprintid}{documents}{$docid}{$compound}{$config{namefieldprefix}}{$name_subfield} = $hash{$key};
								}
								# otherwise we need to create a name hash
								else {
									$eprints{$eprintid}{documents}{$docid}{$compound}{$config{namefieldprefix}} = { $name_subfield => $hash{$key} };
								}								
							}
							# not a name sub-object
							else {
								$eprints{$eprintid}{documents}{$docid}{$compound}{$component} = $hash{$key};
							}
						}
						# otherwise we would be creating another compound field hash, but we do not have a multifield
						else {

							print "WARNING: ignoring redefined value '$hash{$key}' of non-multiple field '$field' (col $cref) on row $rref\n" if $config{warn}{nonmulti};
							next;
						}
					}
				}
				# the compound field is not yet defined for this eprint document so create it (with a row reference)
				else {
					if (is_multifield($field)) {
						# if name sub-object
						if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
							my $name_subfield = $1;
							$eprints{$eprintid}{documents}{$docid}{$compound} = [ { $config{comprowkey} => $row, $config{namefieldprefix} => { $name_subfield => $hash{$key} } } ];
						}
						# not a name sub-object
						else {
							$eprints{$eprintid}{documents}{$docid}{$compound} = [ { $config{comprowkey} => $row, $component => $hash{$key} } ];
						}
					}
					else {
						# if name sub-object
						if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
							my $name_subfield = $1;
							$eprints{$eprintid}{documents}{$docid}{$compound} = { $config{comprowkey} => $row, $config{namefieldprefix} => { $name_subfield => $hash{$key} } };
						}
						# not a name sub-object
						else {
							$eprints{$eprintid}{documents}{$docid}{$compound} = { $config{comprowkey} => $row, $component => $hash{$key} };
						}
					}
				}
			}
			# not compound (NOTE: name sub-object cannot appear outside a compound field so we won't check for it here)
			else {
				if (is_multifield($field)) {
					if (defined $eprints{$eprintid}{documents}{$docid}{$docfield}) {
						push @{$eprints{$eprintid}{documents}{$docid}{$docfield}}, $hash{$key};
					}
					else {
						$eprints{$eprintid}{documents}{$docid}{$docfield} = [ $hash{$key} ];
					}
				}
				else {
					if (defined $eprints{$eprintid}{documents}{$docid}{$docfield}) {
						print "WARNING: ignoring redefined value '$hash{$key}' of non-multiple field '$field' (col $cref) on row $rref\n" if $config{warn}{nonmulti};
						next;
					}
					else {
						$eprints{$eprintid}{documents}{$docid}{$docfield} = $hash{$key};
					}
				}
			}
		}
		# eprint level
		else {
			print "WARNING: ignoring non-empty document-level field '$field' (col '$cref') (value = '$hash{$key}') in eprint-level row (row $rref)\n" if $config{warn}{d_in_e_type} && ($field =~ /^documents\.(.*)/);  
			next if ($field =~ /^documents\.(.*)/);
			# check for compound field
			my ($compound, $component) = is_compound($field);
			if (defined $compound) {
				# if the compound field is defined for this eprint
				if (defined $eprints{$eprintid}{$compound}) {
					if (is_multifield($field)) {
						# if the row is the current one
						if ( $eprints{$eprintid}{$compound}[-1]{$config{comprowkey}} == $row ) {
							# if name sub-object
							if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
								my $name_subfield = $1;
								# if we already have a name hash use it
								if (defined $eprints{$eprintid}{$compound}[-1]{$config{namefieldprefix}}) {
									$eprints{$eprintid}{$compound}[-1]{$config{namefieldprefix}}{$name_subfield} = $hash{$key};
								}
								# otherwise we need to create a name hash
								else {
									$eprints{$eprintid}{$compound}[-1]{$config{namefieldprefix}} = { $name_subfield => $hash{$key} };
								}
							}
							# not a name sub-object
							else {
								$eprints{$eprintid}{$compound}[-1]{$component} = $hash{$key};
							}
						}
						# otherwise we are creating another compound field hash, so push it onto the array
						else {
							# if the field is a name sub-object
							if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
								my $name_subfield = $1;
								push @{$eprints{$eprintid}{$compound}}, { $config{comprowkey} => $row, $config{namefieldprefix} => { $name_subfield => $hash{$key} } };
							}
							else {
								push @{$eprints{$eprintid}{$compound}}, { $config{comprowkey} => $row, $component => $hash{$key} };
							}
						}
					}
					# not a multi-field
					else {
						# if the compound field is defined for this eprint and the row is the current one
						# we must be adding another sub-field to the compound hash
						if ( $eprints{$eprintid}{$compound}{$config{comprowkey}} == $row ) {
							# if a name sub-object
							if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
								my $name_subfield = $1;
								# if we already have a name hash use it
								if (defined $eprints{$eprintid}{$compound}{$config{namefieldprefix}}) {
									$eprints{$eprintid}{$compound}{$config{namefieldprefix}}{$name_subfield} = $hash{$key};
								}
								# otherwise we need to create a name hash
								else {
									$eprints{$eprintid}{$compound}{$config{namefieldprefix}} = { $name_subfield => $hash{$key} };
								}								
							}
							# not a name field
							else {
								$eprints{$eprintid}{$compound}{$component} = $hash{$key};
							}
						}
						else {
							# otherwise we are creating another compound field hash
							print "WARNING: ignoring redefined value '$hash{$key}' of non-multiple field '$field' (col $cref) on row $rref\n" if $config{warn}{nonmulti};
							next;
						}					
					}
				}
				# the compound field is not yet defined for this eprint so create it (with a row reference)
				else {
					# if multi-field
					if (is_multifield($field)) {
						# if name sub-object
						if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
							my $name_subfield = $1;
							$eprints{$eprintid}{$compound} = [ { $config{comprowkey} => $row, $config{namefieldprefix} => { $name_subfield => $hash{$key} } } ];
						}
						# not a name sub-object
						else {
							$eprints{$eprintid}{$compound} = [ { $config{comprowkey} => $row, $component => $hash{$key} } ];
						}
					}
					# not multi-field
					else {
						# if name sub-object
						if ( $component =~ /^$config{namefieldprefix}\^(.*)/ ) {
							my $name_subfield = $1;
							$eprints{$eprintid}{$compound} = { $config{comprowkey} => $row, $config{namefieldprefix} => { $name_subfield => $hash{$key} } };
						}
						# not a name sub-object
						else {
							$eprints{$eprintid}{$compound} = { $config{comprowkey} => $row, $component => $hash{$key} };
						}
					}
				}
			}
			# not compound (NOTE: name sub-object cannot appear outside a compound field so we won't check for it here)
			else {
				if (is_multifield($field)) {
					if (defined $eprints{$eprintid}{$field}) {
						push @{$eprints{$eprintid}{$field}}, $hash{$key};
					}
					else {
						$eprints{$eprintid}{$field} = [ $hash{$key} ];
					}
				}
				else {
					if (defined $eprints{$eprintid}{$field}) {
						print "WARNING: ignoring redefined value '$hash{$key}' of non-multiple field '$field' (col $cref) on row $rref\n" if $config{warn}{nonmulti};
						next;
					}
					else {
						$eprints{$eprintid}{$field} = $hash{$key};
					}
				}
			}
		}
	}
}

# returns a user-readable letter-based column reference
sub colref {
	my $col = shift;
	my $base = shift;
	
	$col += 1 if ! $base;
	return chr(64 + $col) if $col < 27;
	my $base26 = int ($col / 26);
	$col = $col - (26 * $base26);
	return '' if $base26 > 26;
	return chr(64 + $base26).chr(64 + $col);
}

# returns a 1-based row number
sub rowref {
	my $row = shift;
	my $base = shift;
	
	$row += 1 if ! $base;
	return $row;
}

# returns true if fieldname is a prefield
sub is_prefield {
	my $fieldname = shift;
	foreach my $prefield (@{$config{prefields}}) {
		return 1 if $prefield eq $fieldname;
	}
	return 0;
}

# tests if field allows multiple values
sub is_multifield {
	my $f = shift;
	my $s = shift || $schemaname;
	
	return 1 if defined $schema{$s}{$f} && $schema{$s}{$f} eq 'M';
	return 0;
}

# tests if field is compound. If so returns parent field and child field
# NOTE - this only works one layer deep except for documents and creators (special cases)
sub is_compound {
	my $f = shift;
	my $parent;
	my $child;
	my $original = $f;
	
	# remove any documents prefix
	$f = $1 if $f =~ /^documents\.(.*)/;
	
	# remove any creators prefix
	#$f = $1 if $f =~ /^creators\.(.*)/;
	
	# check for evidence of being compound
	if ($f =~ /(.*?)\.(.*)$/ ) {
		$parent = $1;
		$child = $2;
		die "\nERROR: Field '$original' is a multi-level compound field. This type of field is currently not supported\n\n" if $child =~ /\./;
		return ($parent, $child);
	}

	return (undef, undef);
}

#outputs the XML data
sub write_xml {

	my ($eprintid, $field, $value, $subfield, $docid, $dfield, $namefield);
	
	die "\nERROR: Cannot open output file '$opfile'\n\n" if ! open (OP, ">$opfile");
	binmode OP, ':utf8';
	print OP "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
	print OP "<eprints>\n\n";
	
	# eprint level
	foreach $eprintid (sort {$a <=> $b} keys %eprints) {
		print OP "\t<eprint>\n\t\t<eprintid>$eprintid</eprintid>\n";
		foreach $field (keys %{$eprints{$eprintid}}) {
			# deal with document level later
			next if $field eq 'eprintid' || $field eq 'documents';
			# if multi field
			if ( ref($eprints{$eprintid}{$field}) eq 'ARRAY' ) {
				print OP "\t\t\t<$field>\n";
				foreach $value (@{$eprints{$eprintid}{$field}}) {
					# if compound field
					if (ref($value) eq 'HASH') {
						print OP "\t\t\t\t<item>\n";
						foreach $subfield (keys %{$value}) {
							next if $subfield eq $config{comprowkey};
							# if name field (which is a hash ref at the value level)
							if ( ref($$value{$subfield}) eq 'HASH' ) {
								print OP "\t\t\t\t\t<$subfield>\n";
								foreach $namefield (keys %{$$value{$subfield}}) {
									print OP "\t\t\t\t\t\t<$namefield>$$value{$subfield}{$namefield}</$namefield>\n";
								}
								print OP "\t\t\t\t\t</$subfield>\n";
							}
							# not a name field
							else {
								print OP "\t\t\t\t\t<$subfield>$$value{$subfield}</$subfield>\n";
							}
						}
						print OP "\t\t\t\t</item>\n";
					}
					# not compound (should not have name fields here so won't check for them)
					else {
						print OP "\t\t\t\t<item>$value</item>\n";
					}
				}
				print OP "\t\t\t</$field>\n";
			}
			# not multi field
			else {
				$value = $eprints{$eprintid}{$field};
				# if compound field
				if (ref($value) eq 'HASH') {
					print OP "\t\t\t<$field>\n";
					foreach $subfield (keys %{$value}) {
						next if $subfield eq $config{comprowkey};
						# if name field (which is a hash ref at the value level)
						if ( ref($$value{$subfield}) eq 'HASH' ) {
							print OP "\t\t\t\t<$subfield>\n";
							foreach $namefield (keys %{$$value{$subfield}}) {
								print OP "\t\t\t\t\t<$namefield>$$value{$subfield}{$namefield}</$namefield>\n";
							}
							print OP "\t\t\t\t</$subfield>\n";
						}
						# not a name field
						else {
							print OP "\t\t\t\t<$subfield>$$value{$subfield}</$subfield>\n";
						}
					}
					print OP "\t\t\t</$field>\n";
				}
				# not compound field (should not have name fields here so won't check for them)
				else {
					print OP "\t\t\t<$field>$value</$field>\n";
				}			
			}
		}
		
		# now iterate through the default fields to see if they are present
		foreach $dfield (keys %{$config{dfields}}) {
			if (! defined $eprints{$eprintid}{$dfield} ) {
				print OP "\t\t\t<$dfield>" . $config{dfields}{$dfield} . "</$dfield>\n"
			}
		}
		
		# document level
		if (defined $eprints{$eprintid}{documents}) {
			print OP "\t\t\t<documents>\n";
			foreach $docid (sort {$a <=> $b} keys %{$eprints{$eprintid}{documents}}) {
				print OP "\t\t\t\t<document>\n";
				#print OP "\t\t\t\t\t<docid>$docid</docid>\n"; # removed in v1.18
				foreach $field (keys %{$eprints{$eprintid}{documents}{$docid}}) {
					# special case for documents.path
					if ($field eq $config{docpath}{field}) {
						# output the EPrints document format field (based on first file name in array)
						print OP "\t\t\t\t\t<format>".get_doctype(basename($eprints{$eprintid}{documents}{$docid}{$field}[0]))."</format>\n";
						print OP "\t\t\t\t\t<files>\n";
						#we know this field is multiple
						foreach $value (@{$eprints{$eprintid}{documents}{$docid}{$field}}) {
							print OP "\t\t\t\t\t\t<file>\n";
							print OP "\t\t\t\t\t\t\t<datasetid>document</datasetid>\n";
							print OP "\t\t\t\t\t\t\t<filename>".basename($value)."</filename>\n";
							# output the mime-type of the file
							print OP "\t\t\t\t\t\t\t<mime_type>".get_mimetype(basename($value))."</mime_type>\n";
							# brackets around concatinated strings are ESSENTIAL here due to regex priority
							if ( ($config{docpath}{prefix}.$value) =~ /^file\:\/\//i ) {
								print OP "\t\t\t\t\t\t\t<url>".$config{docpath}{prefix}.$value."</url>\n";
							}
							else {
								print OP "\t\t\t\t\t\t\t<url>file://".$config{docpath}{prefix}.$value."</url>\n";
							}
							print OP "\t\t\t\t\t\t</file>\n";
						}
						print OP "\t\t\t\t\t</files>\n";
						next;
					}
					# if multi field
					if ( ref($eprints{$eprintid}{documents}{$docid}{$field}) eq 'ARRAY' ) {
						foreach $value (@{$eprints{$eprintid}{documents}{$docid}{$field}}) {
							print OP "\t\t\t\t\t<$field>\n";
							# if compound field
							if (ref($value) eq 'HASH') {
								print OP "\t\t\t\t\t\t<item>\n";
								foreach $subfield (keys %{$value}) {
									next if $subfield eq $config{comprowkey};
									# if name field (which is a hash ref at the value level)
									if ( ref($$value{$subfield}) eq 'HASH' ) {
										print OP "\t\t\t\t\t\t\t<$subfield>\n";
										foreach $namefield (keys %{$$value{$subfield}}) {
											print OP "\t\t\t\t\t\t\t\t<$namefield>$$value{$subfield}{$namefield}</$namefield>\n";
										}
										print OP "\t\t\t\t\t\t\t</$subfield>\n";
									}
									# not a name field
									else {
										print OP "\t\t\t\t\t\t\t<$subfield>$$value{$subfield}</$subfield>\n";
									}
								}
								print OP "\t\t\t\t\t\t</item>\n";
							}
							# not compound field (should not have name fields here so won't check for them)
							else {
								print OP "\t\t\t\t\t\t<item>$value</item>\n";
							}
							print OP "\t\t\t\t\t</$field>\n";
						}
					}
					# not multi field
					else {
						$value = $eprints{$eprintid}{documents}{$docid}{$field};
						# if compound field
						if (ref($value) eq 'HASH') {
							print OP "\t\t\t\t\t<$field>\n";
							foreach $subfield (keys %{$value}) {
								next if $subfield eq $config{comprowkey};
								# if name field (which is a hash ref at the value level)
								if ( ref($$value{$subfield}) eq 'HASH' ) {
									print OP "\t\t\t\t\t\t<$subfield>\n";
									foreach $namefield (keys %{$$value{$subfield}}) {
										print OP "\t\t\t\t\t\t\t<$namefield>$$value{$subfield}{$namefield}</$namefield>\n";
									}
									print OP "\t\t\t\t\t\t</$subfield>\n";
								}
								# not a name field
								else {
									print OP "\t\t\t\t\t\t<$subfield>$$value{$subfield}</$subfield>\n";
								}
							}
							print OP "\t\t\t\t\t</$field>\n";
						}
						# not compound field (should not have name fields here so won't check for them) 
						else {
							print OP "\t\t\t\t\t<$field>$value</$field>\n";
						}
					}
				}
				print OP "\t\t\t\t</document>\n";
			}
			print OP "\t\t\t</documents>\n";
		}
		print OP "\t</eprint>\n\n";
	}
	print OP "</eprints>\n";	
	close (OP);
}

# displays list of schema names
sub show_schemas {
	print "\nI currently know about the following data schemas: -\n\n";
	foreach my $ds (sort keys %schema) {
		print "\t$ds\n";
	}
	print "\nUse $0 -d <schema> to describe a schema in detail\n";
	exit;
}

# displays details of a schema
sub show_schema {
	my $ds = shift || exit;

	# don't use die here because this sub is invoked from get options
	if (!defined $schema{$ds}) {
		print"\nERROR: Unknown schema '$ds'\n\n";
		exit 1;
	}

	print "\nFields defined in the '$ds' schema: -\n\n";
	print "mandatory? compound?  multi?  fieldname\n";
	print "---------- ---------  ------  ---------\n";
	
	foreach my $pre (@{$config{prefields}}) {
		print "mandatory  simple     single  $pre\n";
	}
	foreach my $fn (sort keys %{$schema{$ds}}) {
		print is_prefield($fn) ? "mandatory  " : "standard   "; 
		print is_compound($fn) ? "compound   " : "simple     "; 
		print is_multifield($fn, $ds) ? "multi   " : "single  ";
		print "$fn\n";
	}
	print "\nNote - the fields above represent the spreadsheet implementation\nof the associated data schema, not the data schema itself.\n\n";
	exit;
}
	
# outputs a tab-indented line of XML with new line at the end
sub xml_out {
	my ($ind, $str, $tag) = @_;
	
	if ( defined $tag ) {
		print OP "\t" x $indent . "<" . $tag . ">" . $str . "</" . $tag . ">\n";
	}
	else {
		print OP "\t" x $indent . $str . "\n";
	}
}

# prints usage information
sub show_usage {
	print "\n" . basename($0) . " - Spreadsheet To EPrints XML Converter\n\nConverts Microsoft .xls spreadsheet files into EPrints XML files\n";
	print "\nUsage:";
	print "  " . basename($0) ." [options] <schema> <xlsfile> <xmlfile>\n\n";
	print "  where\n";
	print "    <schema> = name of data schema to be used (use -s to show known schemas)\n";
	print "    <xlsfile> = path to MS Excel .xls format file (NOT an .xlsx file [yet])\n";
	print "    <xmlfile> = path to EPrints XML output file\n\n";
	print "  options\n";
	print "    -? = shown this help message\n";
	print "    -s = shown list of know schemas\n";
	print "    -d <schema> = describe the <schema> data schema\n";
	print "    -r <num> = ignore the first <num> rows in spreadsheet (default:1)\n";
	print "    -n = no data schema checking except mandatory pre-fields and multi-fields\n";
	print "    -e = explain (verbose), describe actions in detail (assumes -w)\n";
	print "    -E = extra verbose, describe actions in excrutiating detail (assumes -w)\n";
	print "    -w = show warnings, for example when spreadsheet cells are ignored\n";
	print "    -o = overwrite XML output file if it already exists\n";
	print "    -p <path> = prefix document paths with <path>\n";
	print "    -u <userid> = set userid to <userid> (default:1)\n";
	print "    -t <eprint_status> = set eprint_status to <eprint_status> (default:buffer)\n";	
	print "    -v = display version number\n";
	
	exit;
}

# switches on all warning flags in config
sub warnings_on {
	foreach ( keys %{$config{warn}} ) {
		$config{warn}{$_} = 1;
	}
}

# shows version number
sub show_version {
	print "\n" . basename($0) . " - v$config{version}\n\n";
	print "j.beaman\@leeds.ac.uk\n\n";
	exit;
}

# get options from command line and sets the %opt hash keys
sub get_options {
	Getopt::Long::Configure ("bundling");
	GetOptions( 'help|?' => sub { show_usage();},
				'schemas|s' => sub { show_schemas();},
				'describe|d=s' => sub { show_schema($_[1]);},
				'overwrite|o' => \$config{overwrite},
				'warnings|w' => sub { warnings_on(); },
				'version|v' => sub { show_version; },
				'explain|e' => sub { warnings_on(); $config{noise} = 1; },
				'extra|E' => sub { warnings_on(); $config{noise} = 2; },
				'rows|r=i' => \$config{num_header_rows},
				'nocheck|n' => sub { $config{check_fields} = 0; },
				'userid|u=i' => \$config{dfields}{userid},
				'status|t=s' => \$config{dfields}{eprint_status},
				'path|p=s' => \$config{docpath}{prefix},
				);
	# append forward slash to docpath prefix if required
	$config{docpath}{prefix} .= '/' if $config{docpath}{prefix} ne '' && $config{docpath}{prefix} !~ /\/$/;
}

# get external data schemas defined in the file 'stepxml_schemas.dat'
sub get_ext_schemas {
	my ($ext_filename, $schema_data, %ext_schema);
	
	# form the expected file name for external data schemas
	$ext_filename = basename($0) =~ /^(.*)\.(.*?)$/ ? $1 : basename($0);
	$ext_filename .= '_schemas.dat';
	
	# if external data schema file exists
	if ( -f $ext_filename ) {
		# read data
		open  SCHEMAS, $ext_filename or return;
		while (<SCHEMAS>) { $schema_data .= $_; }
		close SCHEMAS;
		# form a hash
		$schema_data = '%ext_schema = ( '. $schema_data . ');';
		# amend internal schema hash with new keys
		if (eval $schema_data) {
			foreach (keys %ext_schema) {
				$schema{$_} = $ext_schema{$_};
			}
		}
		else {
			print "\nWARNING: ignoring bad data schema file\n\n";		
		}
	}
}

# attempt to get document type from doctype hash or mimetype hash
sub get_doctype() {
	my $docname = shift;
	$docname =~ /\.([\w]*)$/;
	my $fext = lc($1);
	return $doctype{$fext} if exists $doctype{$fext};
	if (exists $mimetype{$fext}) {
		#get the mime description part before the forward slash
		$mimetype{$fext} =~ /^([\w\-]*?)\//;
		return $1;
	}
	# if all else fails, return unspecified
	return 'other';
}

# attempt to get mimetype of a document
sub get_mimetype {
	my $docname = shift;
	$docname =~ /\.([\w]*)$/;
	my $fext = lc($1);	
	return $mimetype{$fext} if exists $mimetype{$fext};
	return '';
}

# escape XML characters and remove leading and trailing spaces
sub xml_safe
{
	my $val = shift;
	
	# remove leading, trailing and multiple spaces
	$val =~ s/^\s+|\s+$|\s+(?=\s)//g;
	
	# escape xml characters - we do them all here to be safe
	# but actual requirements are: -
	# for tags:
	# < = &lt;
	# > = &gt; (only for compatibility)
	# & = &amp;
	# for attributes:
	# " = &quot;
	# ' = &apos;

	$val =~ s/&/&amp;/g; # this one has to be done first!
	$val =~ s/</&lt;/g;
	$val =~ s/>/&gt;/g;
	$val =~ s/\"/&quot;/g;
	$val =~ s/'/&apos;/g;
	
	return $val;
	
}

