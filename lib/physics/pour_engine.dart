import 'dart:math' as math;

class PourEngine {
  PourEngine(double fillLevel)
      : displayFill = fillLevel,
        initialFill = fillLevel;

  double displayFill;
  double initialFill;
  double flow = 0;
  double residue = 0;

  void reset(double fillLevel) {
    displayFill = fillLevel;
    initialFill = fillLevel;
    flow = 0;
    residue = 0;
  }

  void syncFill(double fillLevel) {
    if (flow >= 0.01) return;
    displayFill = fillLevel;
    initialFill = fillLevel;
  }

  void step({required double dt, required double pour}) {
    if (displayFill <= 0.001) {
      flow += (0 - flow) * dt * 9;
      return;
    }

    final threshold = 0.58 - displayFill * 0.13;
    final requested = ((pour - threshold) / (1 - threshold))
        .clamp(0.0, 1.0)
        .toDouble();
    flow += (requested - flow) * dt * (requested > flow ? 11 : 5.5);
    flow = flow.clamp(0.0, 1.0).toDouble();

    if (flow <= 0.012) return;
    final rate = 0.03 + flow * flow * 0.54;
    displayFill = (displayFill - rate * dt).clamp(0.0, 0.98).toDouble();
    residue = ((initialFill - displayFill) / math.max(initialFill, 0.01))
        .clamp(0.0, 1.0)
        .toDouble();
  }
}