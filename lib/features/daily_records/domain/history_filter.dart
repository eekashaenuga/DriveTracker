import 'income_activity.dart';
import '../../../core/calculations/analytics_date_range.dart';
import 'daily_activity.dart';

const Object _unset = Object();

class HistoryFilter {
  const HistoryFilter({
    this.vehicleId,
    this.vehicleIds,
    this.recordTypes,
    this.activityTypes,
    this.operatingCostsOnly = false,
    this.type = DailyActivityType.all,
    this.range = AnalyticsDateRange.all,
    this.categoryId,
    this.searchQuery = '',
  });

  final String? vehicleId;
  final List<String>? vehicleIds;
  final Set<DailyActivityType>? recordTypes;
  final Set<IncomeActivityType>? activityTypes;
  final bool operatingCostsOnly;
  bool get isInsightsScope =>
      vehicleIds != null ||
      recordTypes != null ||
      activityTypes != null ||
      operatingCostsOnly;
  final DailyActivityType type;
  final AnalyticsDateRange range;
  final String? categoryId;
  final String searchQuery;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  bool get isDefault {
    return !isInsightsScope &&
        vehicleId == null &&
        type == DailyActivityType.all &&
        range == AnalyticsDateRange.all &&
        categoryId == null &&
        searchQuery.trim().isEmpty;
  }

  HistoryFilter copyWith({
    Object? vehicleId = _unset,
    DailyActivityType? type,
    AnalyticsDateRange? range,
    Object? categoryId = _unset,
    String? searchQuery,
  }) {
    return HistoryFilter(
      vehicleId: vehicleId == _unset ? this.vehicleId : vehicleId as String?,
      vehicleIds: vehicleIds,
      recordTypes: recordTypes,
      activityTypes: activityTypes,
      operatingCostsOnly: operatingCostsOnly,
      type: type ?? this.type,
      range: range ?? this.range,
      categoryId: categoryId == _unset
          ? this.categoryId
          : categoryId as String?,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}
