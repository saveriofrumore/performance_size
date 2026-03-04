/********************************************************************
Thesis: Does Fund Growth Reduce Alpha?
Author: Saverio Francesco Rumore
Program: 01_data_cleaning.do
Date: 15 February 2026
Description: Import and clean monthly fund-level panel dataset
             (no analytical sample selection; no post-treatment controls)
Stata version: 19.5
********************************************************************/

version 19.5
set more off
set varabbrev off

*---------------------------------------------------------------*
* Paths (00_master.do sets ${PROJROOT} and cd's into it)
*---------------------------------------------------------------*
local rawfile   "data_raw/panel_fund_month.csv"
local out_clean "data_clean/panel_fund_month_clean.dta"

*---------------------------------------------------------------*
* Import (keep names as-is; do not silently alter the structure)
*---------------------------------------------------------------*
import delimited using "`rawfile'", clear varnames(1) case(preserve) bindquote(strict)

*---------------------------------------------------------------*
* Required columns (fail fast)
*---------------------------------------------------------------*
local required "fund_id date return_pct risk_free mkt_rf smb hml mom aum"
foreach v of local required {
    capture confirm variable `v'
    if _rc {
        di as error "Missing required variable: `v'"
        error 111
    }
}

*---------------------------------------------------------------*
* Fund identifier: trim and drop structurally invalid IDs only
*---------------------------------------------------------------*
capture confirm string variable fund_id
if _rc {
    tostring fund_id, replace usedisplayformat
}
replace fund_id = strtrim(fund_id)
drop if missing(fund_id)

*---------------------------------------------------------------*
* Convert numerics (robust to comma decimals; only if string)
*---------------------------------------------------------------*
local numvars "aum return_pct risk_free mkt_rf smb hml mom"
foreach v of local numvars {
    capture confirm numeric variable `v'
    if _rc {
        quietly replace `v' = subinstr(`v', ",", ".", .)
        quietly destring `v', replace force
    }
}

*---------------------------------------------------------------*
* Date handling: end-of-month string -> Stata daily -> monthly index
* Expected formats commonly exported: "31/01/2015" (DMY) or "2015-01-31" (YMD)
*---------------------------------------------------------------*
gen double ddate = .
capture confirm string variable date
if !_rc {
    quietly replace ddate = daily(date, "DMY")
    quietly replace ddate = daily(date, "YMD") if missing(ddate)
}
else {
    * If date already numeric, treat it as daily date only if it looks like %td
    quietly replace ddate = date
}
format ddate %td
assert !missing(ddate)

gen mdate = mofd(ddate)
format mdate %tm
drop date ddate

*---------------------------------------------------------------*
* Core constructed variables (no lags here; lagging belongs to regression stage)
*---------------------------------------------------------------*
gen double excess_ret = return_pct - risk_free
gen double log_aum    = log(aum) if aum > 0

*---------------------------------------------------------------*
* Panel keys and integrity checks
*---------------------------------------------------------------*
egen long fundnum = group(fund_id), label
xtset fundnum mdate

* One row per fund-month required
capture noisily isid fundnum mdate
if _rc {
    duplicates report fundnum mdate
    di as error "Dataset is not uniquely identified by fundnum × mdate. Fix upstream export or aggregation."
    error 459
}

*---------------------------------------------------------------*
* Minimal diagnostics (no sample restriction here)
*---------------------------------------------------------------*
count if missing(return_pct)
count if missing(risk_free)
count if missing(mkt_rf) | missing(smb) | missing(hml) | missing(mom)
count if missing(aum) | aum <= 0

*---------------------------------------------------------------*
* Save cleaned panel (intentionally overwrite for full replication)
*---------------------------------------------------------------*
compress
save "`out_clean'", replace
