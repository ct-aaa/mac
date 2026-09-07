$ErrorActionPreference = 'Stop'

# ModelSim 10.5 无法在中文绝对路径下可靠创建 work/_lib.qdb。
# 本脚本临时将项目映射到一个纯 ASCII 盘符，关闭 ModelSim 后自动清理。
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$vsim = 'D:\Modelsim\win64\vsim.exe'
$candidateDrives = @('S:', 'T:', 'U:', 'V:')
$mappedDrive = $null
$existingMappings = subst.exe

foreach ($candidate in $candidateDrives) {
    $drivePattern = '^' + [regex]::Escape($candidate) + '\\:'
    if ($existingMappings -notmatch "(?m)$drivePattern") {
        $mappedDrive = $candidate
        break
    }
}

if ($null -eq $mappedDrive) {
    throw 'S:、T:、U:、V: 均已占用，无法创建 ModelSim 临时 ASCII 路径。'
}

subst.exe $mappedDrive $projectRoot
try {
    Set-Location -LiteralPath "$mappedDrive\sim"

    # 不包含 quit 命令：testbench 执行 $finish 后 GUI 和波形窗口保持打开。
    $doCommands = @'
if {![file exists modelsim.ini]} {vmap -c}
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vlog -sv ../src/mac_lane_q15.sv ../src/mac32_8lane_ctrl.sv ../src/reduce_tree8_q15.sv ../src/mac32_8lane_top.sv ../tb/tb_mac32_8lane_top.sv
vsim -voptargs=+acc work.tb_mac32_8lane_top
add wave -divider {顶层控制}
add wave sim:/tb_mac32_8lane_top/clk
add wave sim:/tb_mac32_8lane_top/rst_n
add wave sim:/tb_mac32_8lane_top/start
add wave sim:/tb_mac32_8lane_top/in_valid
add wave sim:/tb_mac32_8lane_top/in_ready
add wave sim:/tb_mac32_8lane_top/busy
add wave sim:/tb_mac32_8lane_top/result_valid
add wave -radix decimal sim:/tb_mac32_8lane_top/result
add wave -divider {控制器}
add wave -radix unsigned sim:/tb_mac32_8lane_top/dut/u_ctrl/state
add wave -radix unsigned sim:/tb_mac32_8lane_top/dut/u_ctrl/beat_count
add wave sim:/tb_mac32_8lane_top/dut/lane_valid
add wave sim:/tb_mac32_8lane_top/dut/lane_first
add wave sim:/tb_mac32_8lane_top/dut/lane_last
add wave -divider {代表性MAC lane 0}
add wave -radix decimal sim:/tb_mac32_8lane_top/a_in(0)
add wave -radix decimal sim:/tb_mac32_8lane_top/b_in(0)
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/g_mac_lanes(0)/u_lane/product_d1
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/g_mac_lanes(0)/u_lane/acc_out
add wave -divider {三级归约树}
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/u_reduce_tree/sum_l1(0)
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/u_reduce_tree/sum_l2(0)
add wave -radix decimal sim:/tb_mac32_8lane_top/dut/u_reduce_tree/sum_l3
run -all
wave zoom full
'@

    & $vsim -do $doCommands
} finally {
    Set-Location -LiteralPath $projectRoot
    subst.exe $mappedDrive /D
}
