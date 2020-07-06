# from http://wiki.eprints.org/w/Automating_your_maintenance
EPRINTS_ROOT="/usr/share/eprints"
cd $EPRINTS_ROOT/archives
for repo in $(ls -l | grep '^d' | awk '{print $9}'); do
    $EPRINTS_ROOT/bin/send_alerts $repo monthly &> /dev/null
done
