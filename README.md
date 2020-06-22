EPrints tools on Research Data Leeds
====================================

This repository contains additional files found in the EPrints installation on `roadmap2`. The initial list of files found was:

```
	bin/aksync
	bin/aktest
	bin/aktest2
	bin/archive_eprints
	bin/astor_api_check
	bin/astor_data.txt
	bin/astor_data2.txt
	bin/astor_data3.txt
	bin/batchrun
	bin/clone_repo
	bin/difflocal.exclude
	bin/difflocal.sh
	bin/do
	bin/do_cr
	bin/do_ingest
	bin/doi
	bin/doi_all.txt
	bin/doi_hash.txt
	bin/doi_list.txt
	bin/epcheck
	bin/epdate
	bin/filecheck
	bin/flist.sh
	bin/go
	bin/ingest
	bin/ingest_orig
	bin/inprep
	bin/inscan
	bin/jb_batch_extract
	bin/jb_comp_ds
	bin/jb_list.sh
	bin/jb_pull_files
	bin/jb_times.sh
	bin/list_eprints
	bin/load_fields
	bin/local/
	bin/ptest.pl
	bin/rdtest_subs.xml
	bin/researchdata_subs.xml
	bin/set_arkivum_running
	bin/set_for_archive
	bin/set_for_archive_old
	bin/show_config
	bin/sync_l2t.patch
	bin/sync_l2t.sh
	bin/tmp.tmp
	bin/ttt.tttt
	bin/user_admin
	bin/wfinject
	bin/xcounter.sh
	bin/xdata
	bin/ximport
	cgi/abecheck
	cgi/admstats
	cgi/bstats (plus 2 versioned files)
	cgi/datapurge
	cgi/datatool (plus 16 versioned files)
	cgi/dstats
	cgi/dstats.orig
	cgi/flist
	cgi/jb
	cgi/jstats
	cgi/latestxm
	cgi/ttest
	cgi/ttt
	cgi/xcounter
```

This repository has taken the versioned `datatool` and `bstats` CGI scripts and added all versions as tags in this repository (to avoid duplication of files). Some of the files have been moved to bin/local as they are obviously utilities which were used on the command line, but other have been left in place. Some are called by cron tasks so should not be moved without editing the crontab.
