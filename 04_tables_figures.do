/********************************************************************
Thesis: Does Fund Growth Reduce Alpha?
Author: Saverio Francesco Rumore
Program: 04_tables_figures.do
Description: Overhauled tables and figures generation
Stata version: 19.5
********************************************************************/

version 19.5
clear all
set more off
set linesize 120
set varabbrev off

* ------------------------------------------------------------------ *
* Directory and Global Graphics Setup
* ------------------------------------------------------------------ *
local outdir "output"
capture mkdir "`outdir'"
local figdir "`outdir'/figures"
capture mkdir "`figdir'"

* Global graphics settings: Font family Cambria and explicit white backgrounds
graph set window fontface "Cambria"
set scheme s1color

* ------------------------------------------------------------------ *
* Data Loading and Exact Sample Harmonization
* ------------------------------------------------------------------ *
local infile "data_clean/panel_with_alpha36.dta"
local in_ster_03 "`outdir'/estimates_panel.ster"

use "`infile'", clear
xtset fundnum mdate

* Load baseline estimates to define exact estimation sample
estimates use "`in_ster_03'"
estimates restore FE_L1

gen estimation_sample = e(sample) // # Output format: Binary

* Restrict strictly to regression sample to avoid estimation mismatch
keep if estimation_sample == 1 // # Output format: Integer

* ------------------------------------------------------------------ *
* Dynamic Scale Diagnostic
* ------------------------------------------------------------------ *
summarize alpha36, detail // # Output format: Decimal

if r(sd) < 0.1 {
    local bp_scale = 10000 // # Output format: Integer
    display "Alpha detected as decimal. Applying 10,000 multiplier."
}
else {
    local bp_scale = 100 // # Output format: Integer
    display "Alpha detected as percent. Applying 100 multiplier."
}

* ------------------------------------------------------------------ *
* Table Outputs (Strictly.csv format)
* ------------------------------------------------------------------ *

* Table 1a: Summary Statistics for main variables
preserve
    collapse (mean) mean_alpha=alpha36 mean_log_aum=log_aum (sd) sd_alpha=alpha36 sd_log_aum=log_aum (p25) p25_alpha=alpha36 p25_log_aum=log_aum (p50) p50_alpha=alpha36 p50_log_aum=log_aum (p75) p75_alpha=alpha36 p75_log_aum=log_aum // # Output format: Decimal
    export delimited using "`outdir'/table1_summary_stats.csv", replace
restore

* Table 1b: Macro Factor Summaries (Collapsed to strict monthly time series)
preserve
    collapse (first) mkt_rf smb hml mom, by(mdate) // # Output format: Decimal
    collapse (mean) mean_mkt=mkt_rf mean_smb=smb mean_hml=hml mean_mom=mom (sd) sd_mkt=mkt_rf sd_smb=smb sd_hml=hml sd_mom=mom // # Output format: Decimal
    export delimited using "`outdir'/table1_macro_factors_summary.csv", replace
restore

* Table 3: Exporting Core Regression Coefficients
tempfile t3
postfile p3 str20 model str40 term double b se t p N r2w using `t3', replace

foreach M in FE_L1 FE_0 FE_L1_quad FE_L12 FE_grow_L1 {
    quietly estimates restore `M'
    
    local N = e(N) // # Output format: Integer
    local r2 = e(r2_w) // # Output format: Decimal

    foreach term in "L1.log_aum" "log_aum" "c.L1.log_aum#c.L1.log_aum" "L12.log_aum" "L1.D.log_aum" {
        capture local b = _b[`term'] // # Output format: Decimal
        capture local se = _se[`term'] // # Output format: Decimal
        
        if (_rc==0) {
            local t = `b'/`se' // # Output format: Decimal
            local p = 2*ttail(e(df_r), abs(`t')) // # Output format: Decimal
            post p3 ("`M'") ("`term'") (`b') (`se') (`t') (`p') (`N') (`r2')
        }
    }
}
postclose p3

preserve
    use `t3', clear
    export delimited using "`outdir'/table3_key_coefs.csv", replace
restore

* ------------------------------------------------------------------ *
* Econometrically Valid Visualizations (FWL Theorem & Dynamic Bins)
* ------------------------------------------------------------------ *

* Figure 5: FWL-Compliant Binned Scatter Plot
preserve
    * 1. Regress alpha36 on month FEs and fund FEs
    quietly xtreg alpha36 i.mdate, fe // # Output format: Decimal
    predict alpha_res, e // # Output format: Decimal

    * 2. Regress predetermined size on FEs
    quietly gen lag_log_aum = L1.log_aum // # Output format: Decimal
    quietly xtreg lag_log_aum i.mdate, fe // # Output format: Decimal
    predict size_res, e // # Output format: Decimal

    * 3. Binning
    xtile size_bin = size_res, nq(20) // # Output format: Integer

    * 4. Collapse to bin means
    collapse (mean) alpha_res size_res, by(size_bin) // # Output format: Decimal

    * 5. Binned scatter plotting
    twoway (scatter alpha_res size_res, mcolor(navy) msize(small)) ///
           (lfit alpha_res size_res, lcolor(maroon) lwidth(medthick)), ///
        title("Within-Fund Effect of {it:log_aum} on {it:alpha36}", font("Cambria") color(black)) ///
        xtitle("Residualized {it:L1.log_aum}", font("Cambria")) ///
        ytitle("Residualized {it:alpha36}", font("Cambria")) ///
        legend(order(1 "Binned Means" 2 "Linear Fit") region(lcolor(white))) ///
        graphregion(color(white)) plotregion(color(white))
        
    graph export "`figdir'/fig5_FE_binscatter.png", replace width(2000)
restore

* ------------------------------------------------------------------ *
* Dynamic Cross-Sectional Quintiles (No Look-Ahead Bias)
* ------------------------------------------------------------------ *

* Figure 6 & Table 4: Time-Varying Quintiles
preserve
    bysort mdate: xtile size_quintile = L1.log_aum, nq(5) // # Output format: Integer

    collapse (mean) mean_alpha=alpha36 (sd) sd_alpha=alpha36 (count) n_funds=alpha36, by(size_quintile) // # Output format: Decimal

    export delimited using "`outdir'/table4_alpha_by_dynamic_size_quintile.csv", replace

    graph bar mean_alpha, over(size_quintile) ///
        title("Mean Subsequent {it:alpha36} by Dynamic {it:L1.log_aum} Quintile", font("Cambria") color(black)) ///
        ytitle("Mean {it:alpha36}", font("Cambria")) ///
        bcolor(navy) ///
        graphregion(color(white)) plotregion(color(white))
        
    graph export "`figdir'/fig6_dynamic_quintiles.png", replace width(2000)
restore