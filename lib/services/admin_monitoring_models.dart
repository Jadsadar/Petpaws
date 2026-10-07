class ApiRouteStats {
  const ApiRouteStats(
      {required this.route,
      required this.count,
      required this.avgMs,
      required this.maxMs,
      required this.totalMs,
      required this.slowCount});

  final String route;
  final int count;
  final double avgMs;
  final double maxMs;
  final double totalMs;
  final int slowCount;

  factory ApiRouteStats.fromJson(Map<String, dynamic> j) => ApiRouteStats(
        route: j['route'] as String,
        count: (j['count'] as num?)?.toInt() ?? 0,
        avgMs: (j['avgMs'] as num?)?.toDouble() ?? 0,
        maxMs: (j['maxMs'] as num?)?.toDouble() ?? 0,
        totalMs: (j['totalMs'] as num?)?.toDouble() ?? 0,
        slowCount: (j['slowCount'] as num?)?.toInt() ?? 0,
      );
}

class SqlQueryStats {
  const SqlQueryStats(
      {required this.query,
      required this.calls,
      required this.totalMs,
      required this.meanMs,
      required this.rows});

  final String query;
  final int calls;
  final double totalMs;
  final double meanMs;
  final int rows;

  factory SqlQueryStats.fromJson(Map<String, dynamic> j) => SqlQueryStats(
        query: j['query'] as String,
        calls: (j['calls'] as num?)?.toInt() ?? 0,
        totalMs: (j['totalMs'] as num?)?.toDouble() ?? 0,
        meanMs: (j['meanMs'] as num?)?.toDouble() ?? 0,
        rows: (j['rows'] as num?)?.toInt() ?? 0,
      );
}

class PerfStats {
  const PerfStats(
      {required this.routes,
      required this.queries,
      required this.sqlAvailable,
      required this.sqlReason,
      required this.slowThresholdMs,
      required this.since,
      required this.scope});

  final List<ApiRouteStats> routes;
  final List<SqlQueryStats> queries;
  final bool sqlAvailable;
  final String? sqlReason;
  final int slowThresholdMs;
  final DateTime? since;
  final String scope;
  int get totalRequests =>
      routes.fold(0, (total, route) => total + route.count);

  factory PerfStats.fromJson(Map<String, dynamic> j) {
    final sql = (j['queries'] as Map<String, dynamic>?) ?? const {};
    return PerfStats(
      routes: ((j['routes'] as List<dynamic>?) ?? const [])
          .map((e) => ApiRouteStats.fromJson(e as Map<String, dynamic>))
          .toList(),
      queries: ((sql['items'] as List<dynamic>?) ?? const [])
          .map((e) => SqlQueryStats.fromJson(e as Map<String, dynamic>))
          .toList(),
      sqlAvailable: sql['available'] == true,
      sqlReason: sql['reason'] as String?,
      slowThresholdMs: (j['slowThresholdMs'] as num?)?.toInt() ?? 500,
      since: DateTime.tryParse(j['since'] as String? ?? ''),
      scope: j['scope'] as String? ?? 'unknown',
    );
  }
}
