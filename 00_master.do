/********************************************************************
Thesis: Does Fund Growth Reduce Alpha?
Author: Saverio Francesco Rumore
Program: 00_master.do
Date: 15 February 2026
Description: Master script to run the full empirical workflow (replicable)
Stata version: 19.5
********************************************************************/

version 19.5
clear all
set more off
set linesize 120
set varabbrev off

*---------------------------------------------------------------*
* Project root and directory structure
*   data_raw/   : raw inputs (read-only)
*   data_clean/ : intermediate + final .dta outputs
*   code/       : .do files
*   output/     : tables + figures
*   logs/       =: execution logs
*---------------------------------------------------------------*

* >>> EDIT THIS PATH ONCE (project root) <<<
global PROJROOT "C:\Users\saver\OneDrive - Università Commerciale Luigi Bocconi\Documents\Istruzione\Thesis\Data"

cd "${PROJROOT}"

* Create folders if missing (safe if they already exist)
capture mkdir "data_raw"
capture mkdir "data_clean"
capture mkdir "code"
capture mkdir "output"
capture mkdir "logs"

*---------------------------------------------------------------*
* Log (traceability)
*---------------------------------------------------------------*
capture log close _all
log using "logs/00_master.log", replace text name(master)

*---------------------------------------------------------------*
* Run scripts in sequence (modular)
*---------------------------------------------------------------*
do "code/01_data_cleaning.do"
do "code/02_alpha_estimation.do"
do "code/03_panel_regression.do"
do "code/04_tables_figures.do"

log close master
