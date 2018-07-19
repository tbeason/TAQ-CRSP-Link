/* ********************************************************************************* */
/* ******************** W R D S   R E S E A R C H   M A C R O S ******************** */
/* ********************************************************************************* */
/* WRDS Macro: TCLINK                                                                */
/* Summary   : Create TAQ-CRSP Link Table                                            */
/* Date      : September 20, 2010                                                    */  
/* Author    : Rabih Moussawi, WRDS                                                  */
/* Variables : - BEGDATE and ENDDATE are Start and End Dates in YYYYMMDD format      */
/*             - OUTSET: TAQ-CRSP link table output dataset   								 */
/* Revised   :	20180717 by Tyler Beason										                */
/* 				- Updated for new TAQ Specifications (current version 3.0)            */
/* 				- Only works for 'TAQMS' Master files (2011 and up) 		             */
/* 				- Change structure of output table to be more concise		             */
/* ********************************************************************************* */
libname home '~';

%MACRO TCLINK_v3(BEGDATE=20150101,ENDDATE=20151231,OUTSET=home.TCLINKOUT);

/* Check Validity of TAQ Library Assignment */
%if (%sysfunc(libref(taqmsec))) %then %do; libname taq "/wrds/nyse/sasdata/taqms/mast"; %end;
%put; %put ### Start ; %put ;
/* IDEA: Use VINTAGE-SYMBOL as TAQ Primary Key */
/*       Then Link it to PERMNO using CUSIP and Ticker Info */
options nonotes;
%let date1= %sysfunc(inputn(&begdate,yymmdd10.));
%let date2= %sysfunc(inputn(&enddate,yymmdd10.));
 %if &date1<&date2 %then %let NDAYS=%sysfunc(intck(DAY,&date1,&date2));
  %else %let NDAYS=0;
%if &date1 < '01JAN2011'd then do;
	%put ### This macro works for 2011 and newer data only ###;
%end;
/* Begin Loop To Construct a 'Master' TAQ Master Dataset */
%do m=0 %to &NDAYS;
%let date = %sysfunc(intnx(DAY,&date1,&m,E));
%let yyyymmdd = %sysfunc(putn(&date,yymmddn8.));
%let existflag = %sysfunc(exist(taq.mastm_&yyyymmdd));
%put &date &yyyymmdd &existflag;

/* Make Sure that dataset Exist */
%if %sysfunc(exist(taq.mastm_&yyyymmdd))=1 %then
%do;
	%put ### Processing Master Dataset for &yyyymmdd ### ;
	%if &yyyymmdd >= 20161024 and &yyyymmdd < 20171205 %then %do;
		data _mastm(keep=date cusip symbol_root symbol_suffix sec_desc); 
			format DATE date9.;
			set taq.mastm_&yyyymmdd; 
			date=&date;
			rename sym_root = symbol_root sym_suffix = symbol_suffix;
		run;
	%end;
	%else %if &yyyymmdd >= 20171205 %then %do;
		data _mastm(keep=date cusip symbol_root symbol_suffix sec_desc); 
			format DATE date9.;
			set taq.mastm_&yyyymmdd; 
			date=&date;
			symbol_root = strip(scan(symbol_15, 1, ' '));
			symbol_suffix = strip(scan(symbol_15, 2, ' '));
		run;
	%end;
 %else %do;
		data _mastm(keep=date cusip symbol_root symbol_suffix sec_desc); 
			format DATE date9.;
			set taq.mastm_&yyyymmdd; 
			date=&date;			
		run;
 %end;
 %if &m=0 %then %do; data _mast1; set _mastm; run; %end;
  %else %do; proc append base=_mast1 data=_mastm force; run; %end;
 proc sql; drop table _mastm; quit;
%end;
/* End Loop */
%end;


/* Clean TAQ Master Dataset Information */
data _mast2; format CUSIP8 $8.;
set _mast1 (keep=DATE CUSIP symbol_root sec_desc symbol_suffix);
CUSIP = strip(compress(CUSIP," ."));
if not missing(CUSIP)  then CUSIP8=substr(CUSIP,1,8);
if missing(CUSIP) and missing(sec_desc) then delete;

symbol_suffix=compress(symbol_suffix, ,'PCS');
symbol_root=compress(symbol_root, ,'PCS');
sec_desc = upcase(compbl(sec_desc));
symbol_cat = cats(symbol_root,symbol_suffix);

run;

/* Sort Data using DATE-SYMBOL Key */
proc sort data=_mast2 nodupkey; by date symbol_root symbol_suffix cusip; run;



/* Step 1: Link by CUSIP */
/* CRSP: Get all PERMNO-NCUSIP combinations */
proc sql;
create table _msenames 
as select distinct permno, ncusip, comnam 
 from crsp.msenames where not missing(ncusip);
quit;
proc sort data=_msenames nodupkey; by permno ncusip; run;




/* Map TAQ and CRSP using 8-digit CUSIP */
proc sql;
create table _mast3
as select b.permno, a.*, b.comnam
from _mast2 as a left join _msenames as b
on a.cusip8=b.ncusip;
quit;

/* Step 2: Find links for the remaining unmatched cases using Exchange Ticker */
/* Identify Unmatched Cases by Splitting the Sample into Match1 and NoMap1 */
proc sort data=_mast3 nodupkey; by date symbol_root symbol_suffix permno; run;
data _Match1 _NoMap1;
set _mast3;
by date symbol_root symbol_suffix permno;
*if last.symbol_root;
FLAG=(missing(permno));
NAMEDIS=min(spedis(sec_desc,comnam),spedis(comnam,sec_desc));
if not missing(permno) then output _match1;
else output _NoMap1;
run;

/* Add the Matches by Ticker */
data _NoMap2;
set _NoMap1;
where not missing(sec_desc);
drop permno comnam flag namedis;
run;

/* Get entire list of CRSP stocks with Exchange Ticker information */
/* Arrange effective dates for link by Exchange 'Trading' Ticker */
/* Use CRSP Ticker if Trading Ticker is missing */
data _CRSP1;
set crsp.msenames;
if not missing(tsymbol) then SMBL = tsymbol;
else SMBL=ticker;
smbl=compress(smbl, ,'PCS');
if not missing(smbl);
COMNAM=upcase(compbl(comnam));
run;

/* Get date ranges for every permno-ticker combination */
proc sql;
  create table _CRSP2
  as select permno, smbl, comnam,  
              min(namedt)as namedt,max(nameendt) as nameenddt
  from _CRSP1
  where not missing (smbl)
  group by permno, smbl
  order by permno, smbl, namedt;
quit; 

/* Label date range variables and keep only most recent company name */
data _CRSP3;
  set _CRSP2;
  by permno smbl;
  if  last.smbl;
  label namedt="Start date of exch. ticker record";
  label nameenddt="End date of exch. ticker record";
  format namedt nameenddt date9.;
run;



/* Get PERMNO for Unmatched Stocks using Ticker-DATE Match*/
proc sql;
create table _NoMap3 
as select a.*, b.permno,comnam, 
 min(spedis(a.sec_desc,b.comnam),spedis(b.comnam,a.sec_desc)) as NAMEDIS
from _NoMap2 as a, _CRSP3 as b
where a.symbol_root=strip(b.smbl) and a.date between namedt and nameenddt
order by date,symbol_cat,namedis;
quit; 

/* Assign all Ticker Matches a Lower Score than CUSIP Matches */
data _NoMap4;
set _NoMap3;
by date symbol_cat;
if first.symbol_cat;
FLAG=2;
run;



/* Score links using company name spelling distance: 0 is Best */
/* Consolidate Link Table */
data _TAQLINK1;
set _match1 _NoMap4(in=b);
FLAG=FLAG+(NAMEDIS>30);
label FLAG="0.CUSIP+Names, 1.CUSIP, 2.Ticker+Names, 3.Ticker Only";
label NAMEDIS="Spelling Distance between TAQ and CRSP Company Names";
label DATE="TAQ Date";
label CUSIP8='8-digit CUSIP';
label CUSIP ='Full CUSIP Number: 9-digit CUSIP + 3-digit NSCC Exchange ID';
rename CUSIP=CUSIP_FULL CUSIP8=CUSIP;
label SYMBOL_CAT="Concatenated Symbol";
label sec_desc = "Company Name in TAQ";
label COMNAM = "Company Name in CRSP";
run;


/* Some companies may have more than one TICKER-PERMNO link,         */
/* Can Clean the link additionally for one observation per permno-date */
proc sort data=_TAQLINK1 nodupkey; by date symbol_root symbol_suffix; 
	where symbol_root ne ' ';
run;


/* Cautious multi-step lagging procedure */
proc sql;
	create table dates as select distinct date from _TAQLINK1 order by date;
quit;

data dates; set dates;
	lagdate = lag(date);
run;


data _TAQLINK2; 
	merge _TAQLINK1(in=a) dates(in=b);
	by date;
run;

data _TAQLINK2lag; set _TAQLINK2(keep=symbol_root symbol_suffix permno date symbol_cat flag);
	rename symbol_cat = lagsymcat date = lagdate permno = lagperm flag = lagflag;
run;

data _TAQLINK2;
	merge _TAQLINK2(in=a) _TAQLINK2lag;
	by lagdate symbol_root symbol_suffix;
	if a;
run;

proc sort data=_TAQLINK2; by symbol_root symbol_suffix permno date; 
run;

/* Final step: construct continuous ranges for PERMNO-SYMBOL matches */
/* WRDS Master TAQ File is missing info on 20NOV2015, so I manually handle some special cases I found */
data &outset(drop = date lagsymcat lagperm lagflag date1 date2 namedis lagdate lagd); set _TAQLINK2;
	by symbol_root symbol_suffix permno;
	retain date1 date2;
	
	lagd = lag(date);
	
	if first.symbol_root or first.symbol_suffix or first.permno then do;
		date1 = date;
		date2 = date;
		lagd = .;
	end;
	else if symbol_cat = lagsymcat and permno = lagperm and lagd = lagdate and flag = lagflag then do;
		date2 = date;
	end;
	else if symbol_cat = lagsymcat and permno = lagperm and lagdate = '19NOV2015'd then do;
		date2 = date;
	end;
	else if symbol_cat = lagsymcat and permno = lagperm and flag ne lagflag and lagdate ne '19NOV2015'd then do;
		begdt = date1;
		enddt = date2;
		output;
		date1 = date;
		date2 = date;
	end;
	
	if last.symbol_root or last.symbol_suffix or last.permno then do;
		begdt = date1;
		enddt = date2;
		output;
	end;
	
	if permno ne .;
	format begdt enddt date9.;
	label BEGDT = "Link Begin Date";
	label ENDDT = "Link End Date";
run;


/* House Cleaning */
proc sql; 
 drop table _Mast1,_Mast2,_Mast3,_MSENames,_CRSP1,_CRSP2,_CRSP3,
  _Match1,_NoMap1,_NoMap2,_NoMap3,_NoMap4,_TAQLINK1,_TAQLINK1,_TAQLINK2,_TAQLINK2lag; 
quit;

%put; %put ### Done ; %put ;
options notes;

%MEND ;


/* ********************************************************************************* */
/* ******* Material Copyright(2010) Author & Wharton Research Data Services  ******* */
/* ****************************** All Rights Reserved ****************************** */
/* ********************************************************************************* */
