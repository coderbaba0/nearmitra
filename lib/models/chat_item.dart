enum ChatKind { text, file, folder }

class ChatItem {
  ChatItem({
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
  });

  final String peerId;
  final String sender;
  final bool mine;
  final DateTime createdAt;
  final ChatKind kind;
  String? text;
  final String? fileName;
  final String? filePath;
  final int? fileSize;
  final String? status;
  final bool isAi;

  String get formattedTime {
    final hour = createdAt.hour == 0 ? 12 : (createdAt.hour > 12 ? createdAt.hour - 12 : createdAt.hour);
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Map<String, dynamic> toJson() => {
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
      };

  factory ChatItem.fromJson(Map<String, dynamic> json) => ChatItem(
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
      );
}
