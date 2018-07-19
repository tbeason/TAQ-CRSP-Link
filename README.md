# TAQ-CRSP-Link
An updated version of the TCLINK.sas macro from WRDS. The WRDS macro was last updated in 2010 and NYSE has since changed the TAQ specifications, so the macro no longer works properly. This new version, named `TCLINK_v3.sas`, works on the millisecond version of the TAQ Master files, which have consistent data beginning in 2011. The old TCLINK macro will work prior to 2011 with no changes.

The TCLINK_v3 macro returns trading symbol root-symbol suffix-CRSP PERMNO pairings and the continuous date ranges that apply. This is different than the output of the WRDS macro, which had pairings given for each date.
