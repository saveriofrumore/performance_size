/*****************************************************************************
Thesis: Does Fund Growth Reduce Alpha?
Author: Saverio Francesco Rumore
Program: 03_panel_regression.do
Date: 15 February 2026
Description:
    Two-way fixed effects panel regressions relating risk-adjusted performance
    (rolling 36-month Carhart alpha, alpha36) to fund size.

Identification discipline:
    - Within-fund variation via fund fixed effects
    - Common shocks via month fixed effects
    - Predetermined treatment via lagged log(AUM) to mitigate simultaneity
    - Clustered inference at fund level to address serial correlation

Outputs:
    - Saved estimates to output/estimates_panel.ster

Stata version: 19.5
*****************************************************************************/

version 19.5
set more off
set varabbrev off

*---------------------------------------------------------------*
* 0) Paths + settings
*---------------------------------------------------------------*
local infile  "data_clean/panel_with_alpha36.dta"
local outster "output/estimates_panel.ster"

* Minimum within-fund months in the regression sample (set 0 to disable)
local min_T 24

*---------------------------------------------------------------*
* 1) Load + fail-fast checks
*---------------------------------------------------------------*
use "`infile'", clear

local musthave "fundnum mdate alpha36 aum log_aum"
foreach v of local musthave {
    capture confirm variable `v'
    if _rc {
        di as error "Missing required variable: `v'. Stop."
        error 111
    }
}

format mdate %tm
xtset fundnum mdate

*---------------------------------------------------------------*
* 2) Regression sample (AUM restrictions apply HERE, not in alpha construction)
*---------------------------------------------------------------*
gen byte base_sample = !missing(alpha36) & !missing(log_aum) & !missing(aum) & (aum > 0)

* Optional: ensure enough within-fund history in the regression sample
if `min_T' > 0 {
    bys fundnum: egen int T_fund = total(base_sample)
    replace base_sample = 0 if T_fund < `min_T'
    drop T_fund
}

count if base_sample
di as txt "Regression base sample (alpha36 + valid AUM/log_aum): " %12.0fc r(N)

*---------------------------------------------------------------*
* 3) Main specifications (two-way FE via fund FE + i.mdate)
*---------------------------------------------------------------*

* 3.1 Baseline (preferred): predetermined size
xtreg alpha36 L1.log_aum i.mdate if base_sample & !missing(L1.log_aum), ///
    fe vce(cluster fundnum)
estimates store FE_L1

* 3.2 Contemporaneous size (DESCRIPTIVE ONLY; not used for causal interpretation)
xtreg alpha36 log_aum i.mdate if base_sample, ///
    fe vce(cluster fundnum)
estimates store FE_0

* 3.3 Non-linearity / capacity (robustness): quadratic in predetermined size
xtreg alpha36 c.L1.log_aum##c.L1.log_aum i.mdate if base_sample & !missing(L1.log_aum), ///
    fe vce(cluster fundnum)
estimates store FE_L1_quad

* 3.4 Longer lag size (robustness): more predetermined
xtreg alpha36 L12.log_aum i.mdate if base_sample & !missing(L12.log_aum), ///
    fe vce(cluster fundnum)
estimates store FE_L12

* 3.5 Growth (robustness): use L1 change in log AUM to preserve timing discipline
*     NOTE: D.log_aum at time t uses AUM_t and may still react to contemporaneous shocks.
*     Using L1.D.log_aum makes growth predetermined relative to alpha_t.
xtreg alpha36 L1.D.log_aum i.mdate if base_sample & !missing(L1.D.log_aum), ///
    fe vce(cluster fundnum)
estimates store FE_grow_L1

*---------------------------------------------------------------*
* 4) Save estimation set for 04_tables_figures.do (overwrite by design)
*---------------------------------------------------------------*
capture mkdir "output"
estimates save "`outster'", replace

*---------------------------------------------------------------*
* 5) Compact on-screen check
*---------------------------------------------------------------*
estimates table FE_L1 FE_0 FE_L1_quad FE_L12 FE_grow_L1, ///
    b(%9.4f) se(%9.4f) stats(N r2_w)
