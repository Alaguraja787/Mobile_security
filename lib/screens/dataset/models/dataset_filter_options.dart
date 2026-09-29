/// Immutable filter options configuration for querying persisted DatasetRecords.
class DatasetFilterOptions {
  final String? sessionId;
  final String? searchQuery;
  final String? availabilityFilter;
  final DateTime? startTime;
  final DateTime? endTime;
  final bool micActiveOnly;
  final bool cameraActiveOnly;
  final bool foregroundOnly;
  final bool networkOnly;

  const DatasetFilterOptions({
    this.sessionId,
    this.searchQuery,
    this.availabilityFilter,
    this.startTime,
    this.endTime,
    this.micActiveOnly = false,
    this.cameraActiveOnly = false,
    this.foregroundOnly = false,
    this.networkOnly = false,
  });

  bool get hasActiveFilters =>
      (sessionId != null && sessionId!.isNotEmpty) ||
      (searchQuery != null && searchQuery!.trim().isNotEmpty) ||
      (availabilityFilter != null && availabilityFilter!.isNotEmpty) ||
      startTime != null ||
      endTime != null ||
      micActiveOnly ||
      cameraActiveOnly ||
      foregroundOnly ||
      networkOnly;

  int get activeFilterCount {
    int count = 0;
    if (sessionId != null && sessionId!.isNotEmpty) count++;
    if (searchQuery != null && searchQuery!.trim().isNotEmpty) count++;
    if (availabilityFilter != null && availabilityFilter!.isNotEmpty) count++;
    if (startTime != null || endTime != null) count++;
    if (micActiveOnly) count++;
    if (cameraActiveOnly) count++;
    if (foregroundOnly) count++;
    if (networkOnly) count++;
    return count;
  }

  DatasetFilterOptions copyWith({
    String? sessionId,
    bool clearSessionId = false,
    String? searchQuery,
    bool clearSearchQuery = false,
    String? availabilityFilter,
    bool clearAvailabilityFilter = false,
    DateTime? startTime,
    bool clearStartTime = false,
    DateTime? endTime,
    bool clearEndTime = false,
    bool? micActiveOnly,
    bool? cameraActiveOnly,
    bool? foregroundOnly,
    bool? networkOnly,
  }) {
    return DatasetFilterOptions(
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      availabilityFilter: clearAvailabilityFilter
          ? null
          : (availabilityFilter ?? this.availabilityFilter),
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      micActiveOnly: micActiveOnly ?? this.micActiveOnly,
      cameraActiveOnly: cameraActiveOnly ?? this.cameraActiveOnly,
      foregroundOnly: foregroundOnly ?? this.foregroundOnly,
      networkOnly: networkOnly ?? this.networkOnly,
    );
  }

  DatasetFilterOptions reset() {
    return const DatasetFilterOptions();
  }
}
