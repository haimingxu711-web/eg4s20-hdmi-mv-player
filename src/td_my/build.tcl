import_device eagle_s20.db -package EG4S20BG256
open_project my_top.al
reset_runs syn_1
launch_runs {syn_1 phy_1} -jobs 1
wait_run syn_1
wait_run phy_1
close_project
exit
