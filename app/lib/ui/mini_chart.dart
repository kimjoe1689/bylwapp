import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

class MiniChart extends StatelessWidget {
  const MiniChart({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const SizedBox(height: 36);
    }
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final pad = high == low ? 1.0 : 0.0;
    return SizedBox(
      height: 42,
      child: LineChart(
        duration: Duration.zero,
        LineChartData(
          minY: low - pad,
          maxY: high + pad,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              color: color,
              barWidth: 2.4,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
