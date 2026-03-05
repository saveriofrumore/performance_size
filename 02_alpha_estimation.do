/********************************************************************
Thesis: Does Fund Growth Reduce Alpha?
Author: Saverio Francesco Rumore
Program: 02_alpha_estimation.do
Date: 15 February 2026
Description: Rolling 36-month Carhart alpha (fund-month)

Econometric discipline:
  - Alpha is estimated using only fund excess returns and Carhart factors.
  - No AUM-based restrictions are applied in alpha construction (applied only
    in the panel regression stage to avoid mechanical selection).

Implementation discipline:
  - Stata 19.5: rolling does NOT support by(), so we loop fund-by-fund.
  - Keep all successfully estimated rolling windows; do not drop entire funds
    beyond what is mechanically required (window length and missing inputs).
  - Enforce unique (fundnum, mdate) in the alpha file before merging.

Inputs:
  - data_clean/panel_fund_month_clean.dta

Outputs:
  - data_clean/panel_with_alpha36.dta
  
Stata version: 19.5
********************************************************************/

version 19.5
set more off
set varabbrev off

*---------------------------------------------------------------*
* Paths
*---------------------------------------------------------------*
local cleanfile "data_clean/panel_fund_month_clean.dta"
local outfile   "data_clean/panel_with_alpha36.dta"
local window    36

*---------------------------------------------------------------*
* Load data (structural panel)
*---------------------------------------------------------------*
use "`cleanfile'", clear

* Keep only what alpha estimation needs + keys
keep fundnum mdate excess_ret mkt_rf smb hml mom

format mdate %tm
xtset fundnum mdate

*---------------------------------------------------------------*
* Alpha estimation sample (NO AUM restriction here)
*---------------------------------------------------------------*
drop if missing(excess_ret)
drop if missing(mkt_rf) | missing(smb) | missing(hml) | missing(mom)

*---------------------------------------------------------------*
* Rolling 36m Carhart regression fund-by-fund (Stata 19.5 safe)
*---------------------------------------------------------------*
tempfile alpha_all onefund alpha_unique

* Initialize empty accumulator
preserve
    clear
    set obs 0
    gen int    fundnum = .
    gen int    mdate   = .
    gen double alpha36 = .
    save "`alpha_all'", replace
restore

levelsof fundnum, local(funds)

quietly foreach f of local funds {

    preserve
        keep if fundnum == `f'
        sort mdate

        * Need at least `window' valid months to run rolling
        count
        if r(N) < `window' {
            restore
            continue
        }

        * Rolling regression; save results for this fund
        capture noisily rolling alpha36 = _b[_cons] nobs = e(N), window(`window') step(1) ///
            saving("`onefund'", replace): ///
            regress excess_ret mkt_rf smb hml mom
        if _rc {
            restore
            continue
        }

        use "`onefund'", clear

        * Normalize rolling time variable to mdate (endpoint of the window)
        capture confirm variable mdate
        if _rc {
            capture confirm variable end
            if !_rc rename end mdate
            else {
                capture confirm variable _end
                if !_rc rename _end mdate
                else {
                    capture confirm variable _time
                    if !_rc rename _time mdate
                    else {
                        restore
                        continue
                    }
                }
            }
        }

        replace mdate = floor(mdate)
        format mdate %tm

        * Keep only full windows
        drop if missing(nobs) | nobs < `window'

        count
        if r(N) == 0 {
            restore
            continue
        }

        * Keep only merge keys + alpha (do NOT recreate fundnum; it already exists)
        keep fundnum mdate alpha36

        * Append to accumulator
        append using "`alpha_all'"
        save "`alpha_all'", replace
    restore
}

*---------------------------------------------------------------*
* Finalize alpha file: enforce unique (fundnum, mdate)
*---------------------------------------------------------------*
use "`alpha_all'", clear
drop if missing(fundnum) | missing(mdate)

collapse (mean) alpha36, by(fundnum mdate)
isid fundnum mdate

save "`alpha_unique'", replace

*---------------------------------------------------------------*
* Merge alpha back to full structural panel and save
*---------------------------------------------------------------*
use "`cleanfile'", clear
isid fundnum mdate

merge 1:1 fundnum mdate using "`alpha_unique'", nogen

compress
save "`outfile'", replace
