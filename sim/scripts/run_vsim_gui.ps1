$ErrorActionPreference = 'Stop'

# ModelSim 10.5 cannot reliably create work/_lib.qdb under a Unicode path.
# Map the project to a temporary ASCII drive and remove it after vsim closes.
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$vsim = 'D:\Modelsim\win64\vsim.exe'
$candidateDrives = @('S:', 'T:', 'U:', 'V:')
$mappedDrive = $null

foreach ($candidate in $candidateDrives) {
    $driveName = $candidate.TrimEnd(':')
    # Check physical, network and existing subst drives to avoid collisions.
    if ($null -eq (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue)) {
        $mappedDrive = $candidate
        break
    }
}

if ($null -eq $mappedDrive) {
    throw 'S:, T:, U: and V: are all occupied; no temporary drive is available.'
}

subst.exe $mappedDrive $projectRoot
try {
    Set-Location -LiteralPath "$mappedDrive\sim"

    # There is intentionally no quit command: keep the GUI open after $finish.
    $doCommands = @'
if {![file exists modelsim.ini]} {vmap -c}
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vlog ../src/mac_lane_q15.v ../src/mac32_8lane_ctrl.v ../src/reduce_tree8_q15.v ../src/mac32_8lane_top.v ../src/mac_top.v ../tb/tb_mac32_8lane_top.v ../tb/tb_mac_top_fpga.v
vsim -voptargs=+acc work.tb_mac32_8lane_top
add wave -divider {Top control}
add wave sim:/tb_mac32_8lane_top/clk
add wave sim:/tb_mac32_8lane_top/rst_n
add wave sim:/tb_mac32_8lane_top/start
add wave sim:/tb_mac32_8lane_top/in_valid
add wave sim:/tb_mac32_8lane_top/in_ready
add wave sim:/tb_mac32_8lane_top/busy
add wave sim:/tb_mac32_8lane_top/result_valid
add wave -radix decimal sim:/tb_mac32_8lane_top/result
add wave -divider {Controller}
add wave -radix unsigned sim:/tb_mac32_8lane_top/dut/u_ctrl/state
add wave -radix unsigned sim:/tb_mac32_8lane_top/dut/u_ctrl/beat_count
add wave sim:/tb_mac32_8lane_top/dut/lane_valid
add wave sim:/tb_mac32_8lane_top/dut/lane_first
add wave sim:/tb_mac32_8lane_top/dut/lane_last
add wave -divider {Representative MAC lane 0}
add wave -radix decimal {sim:/tb_mac32_8lane_top/a_in[15:0]}
add wave -radix decimal {sim:/tb_mac32_8lane_top/b_in[15:0]}
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/g_mac_lanes(0)/u_lane/product_d1
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/g_mac_lanes(0)/u_lane/acc_out
add wave -divider {Three-stage reduction tree}
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/u_reduce_tree/sum_l1_0
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/u_reduce_tree/sum_l2_0
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/u_reduce_tree/sum_l3
run -all
wave zoom full
'@

    & $vsim -do $doCommands
} finally {
    Set-Location -LiteralPath $projectRoot
    subst.exe $mappedDrive /D
}
