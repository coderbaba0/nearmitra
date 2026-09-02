enum ChatKind { text, file, folder }

class ChatItem {
  ChatItem({
    String? id,
    required this.peerId,
    required this.sender,
    required this.mine,
    required this.createdAt,
    required this.kind,
    this.text,
    this.fileName,
    this.filePath,
    this.fileSize,
    this.status,
    this.isAi = false,
    this.isMeshRelay = false,
    this.relayHops,
    this.reaction,
  }) : id = id ?? '${createdAt.millisecondsSinceEpoch}_$peerId';

  final String id;
  final String peerId;
  final String sender;
  final bool mine;
  final DateTime createdAt;
  final ChatKind kind;
  String? text;
  final String? fileName;
  final String? filePath;
  final int? fileSize;
  String? status;
  final bool isAi;
  final bool isMeshRelay;
  final List<String>? relayHops;
  String? reaction;

  String get formattedTime {
    final hour = createdAt.hour == 0
        ? 12
        : (createdAt.hour > 12 ? createdAt.hour - 12 : createdAt.hour);
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String get formattedSize {
    if (fileSize == null || fileSize! <= 0) return '';
    final bytes = fileSize!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'peerId': peerId,
        'sender': sender,
        'mine': mine,
        'createdAt': createdAt.toIso8601String(),
        'kind': kind.name,
        'text': text,
        'fileName': fileName,
        'filePath': filePath,
        'fileSize': fileSize,
        'status': status,
        'isAi': isAi,
        'isMeshRelay': isMeshRelay,
        if (relayHops != null) 'relayHops': relayHops,
        'reaction': reaction,
      };

  factory ChatItem.fromJson(Map<String, dynamic> json) => ChatItem(
        id: json['id'] as String?,
        peerId: json['peerId'] as String,
        sender: json['sender'] as String,
        mine: json['mine'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
        kind: ChatKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => ChatKind.text,
        ),
        text: json['text'] as String?,
        fileName: json['fileName'] as String?,
        filePath: json['filePath'] as String?,
        fileSize: json['fileSize'] as int?,
        status: json['status'] as String?,
        isAi: json['isAi'] == true,
        isMeshRelay: json['isMeshRelay'] == true,
        relayHops: (json['relayHops'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(),
        reaction: json['reaction'] as String?,
      );
}
