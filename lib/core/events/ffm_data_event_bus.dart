import 'dart:async';

/// Event types for global data changes
enum FfmDataEventType {
  /// Transaction created, updated, or deleted
  transactionChanged,
  
  /// Activity session created, updated, or deleted
  activityChanged,
  
  /// Daily note created, updated, or deleted
  dailyNoteChanged,
  
  /// Reminder created, updated, or deleted
  reminderChanged,
  
  /// Goal created, updated, or deleted
  goalChanged,
  
  /// Asset created, updated, or deleted
  assetChanged,
  
  /// Liability created, updated, or deleted
  liabilityChanged,
  
  /// Budget created, updated, or deleted
  budgetChanged,
  
  /// Utility meter or token changed
  utilityMeterChanged,
  
  /// General data invalidation (e.g., after batch operations)
  dataInvalidated,
}

/// Event payload for data changes
class FfmDataEvent {
  const FfmDataEvent({
    required this.type,
    this.entityId,
    this.timestamp,
  });

  final FfmDataEventType type;
  final String? entityId;
  final DateTime? timestamp;

  @override
  String toString() {
    return 'FfmDataEvent(type: $type, entityId: $entityId, timestamp: $timestamp)';
  }
}

/// Global event bus for reactive data updates across the app
/// 
/// Usage:
/// 1. Subscribe to events: `FfmDataEventBus.instance.on<T>().listen(...)`
/// 2. Emit events: `FfmDataEventBus.instance.emit(event)`
/// 3. Dispose subscriptions when widget is disposed
class FfmDataEventBus {
  FfmDataEventBus._();

  static final FfmDataEventBus instance = FfmDataEventBus._();

  final _controller = StreamController<FfmDataEvent>.broadcast();

  /// Stream of all data events
  Stream<FfmDataEvent> get on => _controller.stream;

  /// Stream filtered by event type
  Stream<FfmDataEvent> onType(FfmDataEventType type) {
    return _controller.stream.where((event) => event.type == type);
  }

  /// Stream filtered by entity ID
  Stream<FfmDataEvent> onEntity(String entityId) {
    return _controller.stream.where((event) => event.entityId == entityId);
  }

  /// Emit a data event
  void emit(FfmDataEvent event) {
    _controller.add(FfmDataEvent(
      type: event.type,
      entityId: event.entityId,
      timestamp: event.timestamp ?? DateTime.now(),
    ));
  }

  /// Dispose the event bus (only for testing)
  void dispose() {
    _controller.close();
  }
}
