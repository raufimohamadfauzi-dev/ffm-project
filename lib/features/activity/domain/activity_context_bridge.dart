import 'entities/activity_entity.dart';
import '../presentation/bloc/activity_bloc.dart';

/// Single source of truth bridge between [ActivityBloc] (in-memory state)
/// and the Assistant Agent Harness.
///
/// Ensures assistant plugins always receive an immutable, up-to-date
/// [ActivityLiveSnapshot] representing screen state without querying database directly.
class ActivityContextBridge {
  const ActivityContextBridge(this._activityBloc);

  final ActivityBloc _activityBloc;

  /// Returns an immutable live snapshot of current active sessions, checkpoints,
  /// revision counter, and last updated timestamp.
  ActivityLiveSnapshot get snapshot => _activityBloc.state.toSnapshot();

  int get currentRevision => _activityBloc.state.revision;

  bool get hasActiveSessions => _activityBloc.state.activeSessions.isNotEmpty;
}
