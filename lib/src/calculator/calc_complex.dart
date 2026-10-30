/// Complex arithmetic for the engineering calculator.
///
/// The calculator uses one complex type for every numeric value so a single
/// code path serves real and complex expressions. Real results keep an
/// imaginary part of exactly zero.
library;

import 'dart:math' as math;

/// An immutable complex number in rectangular form.
class CalcComplex {
  const CalcComplex(this.re, this.im);

  const CalcComplex.real(this.re) : im = 0.0;

  static const zero = CalcComplex(0.0, 0.0);
  static const one = CalcComplex(1.0, 0.0);
  static const imaginaryUnit = CalcComplex(0.0, 1.0);

  final double re;
  final double im;

  bool get isReal => im == 0.0;

  double get magnitude => math.sqrt(re * re + im * im);

  /// Phase in radians in the interval (-pi, pi].
  double get phase => math.atan2(im, re);

  double get magnitudeSquared => re * re + im * im;

  CalcComplex operator +(CalcComplex other) =>
      CalcComplex(re + other.re, im + other.im);

  CalcComplex operator -(CalcComplex other) =>
      CalcComplex(re - other.re, im - other.im);

  CalcComplex operator -() => CalcComplex(-re, -im);

  CalcComplex operator *(CalcComplex other) =>
      CalcComplex(re * other.re - im * other.im, re * other.im + im * other.re);

  CalcComplex operator /(CalcComplex other) {
    final denominator = other.magnitudeSquared;
    if (denominator == 0.0) {
      throw const ComplexDivisionByZero();
    }
    return CalcComplex(
      (re * other.re + im * other.im) / denominator,
      (im * other.re - re * other.im) / denominator,
    );
  }

  CalcComplex conjugate() => CalcComplex(re, -im);

  /// Raises [this] to an integer power without losing precision for small
  /// exponents.
  CalcComplex integerPower(int exponent) {
    if (exponent == 0) return one;
    var result = one;
    var base = this;
    var remaining = exponent.abs();
    while (remaining > 0) {
      if (remaining.isOdd) result = result * base;
      remaining >>= 1;
      if (remaining > 0) base = base * base;
    }
    return exponent < 0 ? one / result : result;
  }

  /// Principal power using the exponential form.
  CalcComplex pow(CalcComplex exponent) {
    if (exponent.isReal) {
      final integer = exponent.re;
      if (integer == integer.roundToDouble() && integer.abs() <= 1024) {
        return integerPower(integer.toInt());
      }
    }
    if (this == zero) {
      if (exponent.re > 0) return zero;
      throw const ComplexDomainError('zero cannot be raised to this power');
    }
    final log = ln();
    return (exponent * log).exp();
  }

  /// Principal square root.
  CalcComplex sqrt() {
    if (isReal && re >= 0) return CalcComplex.real(math.sqrt(re));
    final magnitude = this.magnitude;
    final realPart = math.sqrt((magnitude + re) / 2);
    final imagPart = math.sqrt((magnitude - re) / 2) * (im < 0 ? -1 : 1);
    return CalcComplex(realPart, imagPart);
  }

  CalcComplex exp() {
    final scale = math.exp(re);
    return CalcComplex(scale * math.cos(im), scale * math.sin(im));
  }

  /// Principal natural logarithm.
  CalcComplex ln() {
    if (this == zero) {
      throw const ComplexDomainError('ln(0) is undefined');
    }
    return CalcComplex(math.log(magnitude), phase);
  }

  CalcComplex sin() =>
      CalcComplex(math.sin(re) * _cosh(im), math.cos(re) * _sinh(im));

  CalcComplex cos() =>
      CalcComplex(math.cos(re) * _cosh(im), -math.sin(re) * _sinh(im));

  CalcComplex tan() => sin() / cos();

  /// Creates a complex number from magnitude and phase in radians.
  static CalcComplex fromPolar(double magnitude, double phaseRadians) =>
      CalcComplex(
        magnitude * math.cos(phaseRadians),
        magnitude * math.sin(phaseRadians),
      );

  @override
  bool operator ==(Object other) =>
      other is CalcComplex && other.re == re && other.im == im;

  @override
  int get hashCode => Object.hash(re, im);

  @override
  String toString() => isReal ? '$re' : '$re + ${im}j';

  static double _sinh(double value) => (math.exp(value) - math.exp(-value)) / 2;

  static double _cosh(double value) => (math.exp(value) + math.exp(-value)) / 2;
}

/// Division by a complex zero.
class ComplexDivisionByZero implements Exception {
  const ComplexDivisionByZero();
}

/// A complex operation outside its domain (for example `ln(0)`).
class ComplexDomainError implements Exception {
  const ComplexDomainError(this.message);
  final String message;

  @override
  String toString() => message;
}
