class WalkieTalkieGroup {
  final int groupId;
  final String groupName;
  final String description;
  final bool canInitiate;
  final bool canSpeak;
  final bool canListen;
  final int priorityLevel;

  const WalkieTalkieGroup({
    required this.groupId,
    required this.groupName,
    required this.description,
    required this.canInitiate,
    required this.canSpeak,
    required this.canListen,
    required this.priorityLevel,
  });

  factory WalkieTalkieGroup.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) =>
        value is int ? value : int.tryParse('${value ?? 0}') ?? 0;
    bool parseBool(dynamic value) {
      if (value is bool) return value;
      final normalized = '${value ?? ''}'.toLowerCase();
      return normalized == 'true' || normalized == '1';
    }

    return WalkieTalkieGroup(
      groupId: parseInt(json['GroupID'] ?? json['groupId']),
      groupName: '${json['GroupName'] ?? json['groupName'] ?? ''}',
      description: '${json['Description'] ?? json['description'] ?? ''}',
      canInitiate: parseBool(json['CanInitiate'] ?? json['canInitiate']),
      canSpeak: parseBool(json['CanSpeak'] ?? json['canSpeak']),
      canListen: parseBool(json['CanListen'] ?? json['canListen']),
      priorityLevel: parseInt(json['PriorityLevel'] ?? json['priorityLevel']),
    );
  }
}

class WalkieTalkieAccessToken {
  final String provider;
  final String serverUrl;
  final String roomName;
  final String token;
  final String identity;
  final String displayName;
  final bool canPublish;
  final bool canSubscribe;
  final int expiresInSeconds;

  const WalkieTalkieAccessToken({
    required this.provider,
    required this.serverUrl,
    required this.roomName,
    required this.token,
    required this.identity,
    required this.displayName,
    required this.canPublish,
    required this.canSubscribe,
    required this.expiresInSeconds,
  });

  factory WalkieTalkieAccessToken.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) =>
        value is int ? value : int.tryParse('${value ?? 0}') ?? 0;
    bool parseBool(dynamic value) {
      if (value is bool) return value;
      final normalized = '${value ?? ''}'.toLowerCase();
      return normalized == 'true' || normalized == '1';
    }

    return WalkieTalkieAccessToken(
      provider: '${json['Provider'] ?? json['provider'] ?? ''}',
      serverUrl: '${json['ServerUrl'] ?? json['serverUrl'] ?? ''}',
      roomName: '${json['RoomName'] ?? json['roomName'] ?? ''}',
      token: '${json['Token'] ?? json['token'] ?? ''}',
      identity: '${json['Identity'] ?? json['identity'] ?? ''}',
      displayName: '${json['DisplayName'] ?? json['displayName'] ?? ''}',
      canPublish: parseBool(json['CanPublish'] ?? json['canPublish']),
      canSubscribe: parseBool(json['CanSubscribe'] ?? json['canSubscribe']),
      expiresInSeconds:
          parseInt(json['ExpiresInSeconds'] ?? json['expiresInSeconds']),
    );
  }
}
