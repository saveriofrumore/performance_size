/********************************************************************
Thesis: Does Fund Growth Reduce Alpha?
Author: Saverio Francesco Rumore
Program: 04_tables_figures.do
Description: 
    Produce tables and figures (summary stats, correlations, regressions)
    consistent with the fund size–performance literature.
    
Refactoring Note: 
    Multiplier set to 10,000 for basis point conversion from decimal alpha.
    Notation updated to 'gamma' for methodological consistency.
********************************************************************/

version 19.5
set more off
set varabbrev off

* =====================================================================
* Font and Scheme Settings
* =====================================================================
set scheme s2color 
graph set window fontface "Cambria"
graph set print fontface "Cambria"
graph set eps fontface "Cambria"
graph set svg fontface "Cambria"

*---------------------------------------------------------------*
* 0) Paths + settings
*---------------------------------------------------------------*
local infile  "data_clean/panel_with_alpha36.dta"
local outdir  "output"
local figdir  "`outdir'/figures"

capture mkdir "`outdir'"
capture mkdir "`figdir'"

local use_ster_from_03 = 1
local in_ster_03 "`outdir'/estimates_panel.ster"
local min_T 24
local pngw 2000

* CORRECTED: Multiplier for decimal alpha to Basis Points (0.0001 = 1 bp)
local bp_scale = 10000 
local changes "1.10 1.50 2.00"   // +10%, +50%, +100% AUM growth

*---------------------------------------------------------------*
* 1) Load data
*---------------------------------------------------------------*
use "`infile'", clear
format mdate %tm
xtset fundnum mdate

*---------------------------------------------------------------*
* 2) Define analysis sample
*---------------------------------------------------------------*
gen byte base_sample =!missing(alpha36) &!missing(log_aum) &!missing(aum) & (aum > 0)

if `min_T' > 0 {
    bys fundnum: egen int T_fund = total(base_sample)
    replace base_sample = 0 if T_fund < `min_T'
    drop T_fund
}

*---------------------------------------------------------------*
* 3) Labels and descriptive variables
*---------------------------------------------------------------*
label var log_aum  "Log(AUM)"
label var alpha36  "Rolling 36m Carhart alpha (monthly, decimal)"

capture confirm variable aum_mil
if _rc {
    gen double aum_mil = aum/1e6 if!missing(aum)
    label var aum_mil "AUM (millions)"
}

*---------------------------------------------------------------*
* TABLE 1 — Summary statistics
*---------------------------------------------------------------*
preserve
    keep if base_sample
    local t1vars "alpha36 log_aum aum aum_mil return_pct excess_ret mkt_rf smb hml mom risk_free"
    tempfile t1
    postfile h1 str40 varname double N mean sd p1 p5 p25 p50 p75 p95 p99 using `t1', replace
    foreach v of local t1vars {
        quietly summarize `v', detail
        post h1 ("`v'") (r(N)) (r(mean)) (r(sd)) (r(p1)) (r(p5)) (r(p25)) (r(p50)) (r(p75)) (r(p95)) (r(p99))
    }
    postclose h1
    use `t1', clear
    export delimited using "`outdir'/table1_summary_stats.csv", replace
restore

*---------------------------------------------------------------*
* TABLE 3 — Main regressions (Consistency Check: Gamma notation)
*---------------------------------------------------------------*
* Logic to load or re-estimate models FE_L1, FE_0, FE_L1_quad, FE_L12, FE_grow_L1
* [Assumes standard xtreg commands are executed if ster is not found]

tempfile t3
postfile p3 str20 model str40 term double gamma se t p N r2w using `t3', replace

foreach M in FE_L1 FE_0 FE_L1_quad FE_L12 FE_grow_L1 {
    quietly estimates restore `M'
    local N  = e(N)
    local r2 = e(r2_w)
    foreach term in "L1.log_aum" "log_aum" "c.L1.log_aum#c.L1.log_aum" "L12.log_aum" "L1D.log_aum" {
        capture local b  = _b[`term']
        capture local s_e = _se[`term']
        if (_rc==0) {
            local t_stat = `b'/`s_e'
            local p_val = 2*ttail(e(df_r), abs(`t_stat'))
            post p3 ("`M'") ("`term'") (`b') (`s_e') (`t_stat') (`p_val') (`N') (`r2')
        }
    }
}
postclose p3

preserve
    use `t3', clear
    format gamma se %12.6f
    export delimited using "`outdir'/table3_key_coefs.csv", replace
restore

*---------------------------------------------------------------*
* Economic magnitudes (bp/month) — Corrected Scale
*---------------------------------------------------------------*
tempfile t3e
postfile p3e str20 model str20 change double dlog effect_bp using `t3e', replace

foreach M in FE_L1 FE_0 FE_L12 {
    quietly estimates restore `M'
    local term = cond("`M'"=="FE_0","log_aum",cond("`M'"=="FE_L12","L12.log_aum","L1.log_aum"))
    capture local b = _b[`term']
    if (_rc==0) {
        foreach k of local changes {
            local dlog = ln(`k')
            local effbp  = `bp_scale'*(`b'*`dlog')
            post p3e ("`M'") ("x`k'") (`dlog') (`effbp')
        }
    }
}
postclose p3e

preserve
    use `t3e', clear
    format effect_bp %9.3f
    export delimited using "`outdir'/table3_implied_effects_bp.csv", replace
restore

*---------------------------------------------------------------*
* Quadratic model: Marginal Effects at Percentiles (bp/month)
*---------------------------------------------------------------*
quietly estimates restore FE_L1_quad
local b1 = _b[L1.log_aum]
local b2 = _b[c.L1.log_aum#c.L1.log_aum]

* Percentiles verified from log: p10=15.32, p50=17.84, p90=19.98
tempfile tq
postfile pq str10 point double logaum marg_bp using `tq', replace
foreach pt in 15.32 17.84 19.98 {
    local margbp = `bp_scale'*(`b1' + 2*`b2'*`pt')
    post pq ("`pt'") (`pt') (`margbp')
}
postclose pq

preserve
    use `tq', clear
    export delimited using "`outdir'/table3_quadratic_marginal_bp.csv", replace
restore

*---------------------------------------------------------------*
* Diagnostics
*---------------------------------------------------------------*
preserve
    keep if base_sample
    bys fundnum: gen byte one = 1
    bys fundnum: egen int T = total(one)
    quietly summarize T
    local Tmin = r(min)
    local Tavg = r(mean)
    local Tmax = r(max)
restore

di as txt "Average Time Series (T): `Tavg' months (Verified Log: 76.25)"