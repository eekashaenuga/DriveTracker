import 'income_activity.dart';
import '../../../core/calculations/analytics_date_range.dart';
import 'daily_activity.dart';

enum HistorySort { newest, oldest }

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
    this.sort = HistorySort.newest,
    this.selectedActivityType,
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
  final HistorySort sort;
  final IncomeActivityType? selectedActivityType;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  bool get isDefault {
    return !isInsightsScope &&
        vehicleId == null &&
        type == DailyActivityType.all &&
        range == AnalyticsDateRange.all &&
        categoryId == null &&
        selectedActivityType == null &&
        sort == HistorySort.newest &&
        searchQuery.trim().isEmpty;
  }

  HistoryFilter copyWith({
    Object? vehicleId = _unset,
    DailyActivityType? type,
    AnalyticsDateRange? range,
    Object? categoryId = _unset,
    String? searchQuery,
    HistorySort? sort,
    Object? selectedActivityType = _unset,
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
      sort: sort ?? this.sort,
      selectedActivityType: selectedActivityType == _unset
          ? this.selectedActivityType
          : selectedActivityType as IncomeActivityType?,
    );
  }
}
