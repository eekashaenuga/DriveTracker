import '../../../core/utilities/money.dart';

String earningsMoney(num? minor) => minor == null
    ? 'Unavailable'
    : '${minor < 0 ? '-' : ''}${MoneyAmount.formatMinor(minor.abs().round())}';
