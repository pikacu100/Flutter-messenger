import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_messenger/services/chat/chat_service.dart';
import 'package:flutter_messenger/services/chat/typing_indicator.dart';
import 'package:flutter_messenger/services/encryption.dart';
import 'package:flutter_messenger/style.dart';

class ChatPage extends StatefulWidget {
  final String receiverUserNickname;
  final String receiverUserId;
  const ChatPage({
    super.key,
    required this.receiverUserNickname,
    required this.receiverUserId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final ScrollController _scrollController = ScrollController();
  late String chatRoomId;
  late String currentUserId;
  late TypingIndicator _typingIndicator;
  Timer? _typingTimer;
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser!.uid;
    chatRoomId = getChatRoomId(currentUserId, widget.receiverUserId);
    _typingIndicator =
        TypingIndicator(chatRoomId, currentUserId, widget.receiverUserId);
    _markMessagesAsSeen();
  }

  void sendMessage() async {
    if (_messageController.text.isNotEmpty) {
      await _chatService.sendMessage(
        message: _messageController.text,
        receiverId: widget.receiverUserId,
      );
      _messageController.clear();
      _clearTypingStatus();
      _scrollToBottom();
    }
  }

  void _markMessagesAsSeen() {
    _chatService.markMessagesAsSeen(otherUserId: widget.receiverUserId);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String formatTimeStamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    String minutes =
        dateTime.minute < 10 ? '0${dateTime.minute}' : '${dateTime.minute}';
    return '${dateTime.hour}:$minutes';
  }

  String getChatRoomId(String userId, String anotherUserId) {
    List<String> chatIds = [userId, anotherUserId];
    chatIds.sort();
    return chatIds.join('_');
  }

  String decryptMessage(String encryptedMessage) {
    return EncryptionService.decrypt(encryptedMessage, chatRoomId);
  }

  void detectTyping() {
    _typingTimer?.cancel();
    _typingIndicator.updateTypingStatus(true);
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _clearTypingStatus();
    });
  }

  void _clearTypingStatus() {
    _typingIndicator.updateTypingStatus(false);
  }

  void _copyMessageContent(String message) {
    Clipboard.setData(ClipboardData(text: message)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 500),
          content: Text(
            'Message copied to clipboard!',
            style: TextStyle(
              fontSize: 16,
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _clearTypingStatus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(widget.receiverUserNickname),
        centerTitle: true,
        titleTextStyle: FontStyles().appBarStyle(isDarkMode),
        surfaceTintColor:
            isDarkMode ? Colors.grey.shade900 : Colors.grey.shade300,
        leading: IconButton(
          icon: const Icon(
            Icons.navigate_before,
            size: 25,
          ),
          color: isDarkMode ? Colors.white : Colors.grey.shade900,
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5),
        child: Column(
          children: [
            Expanded(
              child: _buildMessageList(),
            ),
            StreamBuilder<bool>(
              stream: _typingIndicator.isReceiverTyping(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data == true) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Text(
                          '${widget.receiverUserNickname} is typing...',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              },
            ),
            _buildMessageInput(isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder(
        stream: _chatService.getMessages(
            userId: widget.receiverUserId, anotherUserId: currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(
              color: Colors.blue,
            ));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
                child: Text('No messages yet, Start chatting!'));
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_isFirstLoad) {
              _scrollToBottom();
              _isFirstLoad = false;
            } else if (snapshot.hasData &&
                snapshot.data!.docs.isNotEmpty &&
                _scrollController.hasClients &&
                _scrollController.position.maxScrollExtent > 0) {
              if (_scrollController.position.pixels >=
                  _scrollController.position.maxScrollExtent - 150) {
                _scrollToBottom();
              }
            }
          });

          final docs = snapshot.data!.docs;
          List<Widget> messageWidgets = [];

          for (int i = 0; i < docs.length; i++) {
            final currentDoc = docs[i];
            final bool isLastInGroup = _isLastMessageInTimeGroup(docs, i);

            messageWidgets
                .add(_buildMessageItem(currentDoc, showTime: isLastInGroup));
          }

          return ListView(
            controller: _scrollController,
            children: messageWidgets,
          );
        });
  }

  bool _isLastMessageInTimeGroup(List<QueryDocumentSnapshot> docs, int index) {
    if (index == docs.length - 1) {
      return true;
    }

    final currentData = docs[index].data() as Map<String, dynamic>;
    final nextData = docs[index + 1].data() as Map<String, dynamic>;

    if (currentData['senderId'] != nextData['senderId']) {
      return true;
    }

    final currentTime = (currentData['timestamp'] as Timestamp).toDate();
    final nextTime = (nextData['timestamp'] as Timestamp).toDate();
    final timeDifference = nextTime.difference(currentTime).inMinutes;

    return timeDifference >= 5;
  }

  Widget _buildMessageItem(DocumentSnapshot snapshot,
      {required bool showTime}) {
    Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

    var isMe = data['senderId'] == currentUserId;
    var alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    var color = isMe ? Colors.blue[100] : Colors.grey[300];

    bool hasBeenSeen = false;
    if (isMe && data['seen'] != null) {
      hasBeenSeen = data['seen'][widget.receiverUserId] ?? false;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Align(
        alignment: alignment,
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPressStart: (LongPressStartDetails details) {
                _showMessageOptionsAtPosition(
                  context,
                  details.globalPosition,
                  snapshot.id,
                  isMe,
                  decryptMessage(
                    data['message'],
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  decryptMessage(
                    data['message'],
                  ),
                  style: TextStyle(color: Colors.grey.shade900),
                ),
              ),
            ),
            if (showTime)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatTimeStamp(data['timestamp']),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  if (isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Icon(
                        hasBeenSeen ? Icons.done_all : Icons.done,
                        size: 14.0,
                        color: hasBeenSeen ? Colors.blue : Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptionsAtPosition(BuildContext context, Offset position,
      String messageId, bool isMe, String message) {
    final RelativeRect popupPosition = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    );

    showMenu(
      context: context,
      position: popupPosition,
      surfaceTintColor: Colors.grey.shade900,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      items: [
        if (isMe)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete),
                SizedBox(width: 8),
                Text('Delete Message'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.content_copy),
              SizedBox(width: 8),
              Text('Copy Message'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        ChatService().deleteMessage(
            userId: widget.receiverUserId,
            anotherUserId: currentUserId,
            docId: messageId);
      } else if (value == 'copy') {
        _copyMessageContent(message);
      }
    });
  }

  Widget _buildMessageInput(bool isDarkMode) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _messageController,
            onChanged: (_) => detectTyping(),
            cursorColor: Colors.blueAccent,
            decoration: InputDecoration(
              hintText: 'Send message...',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              border: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.transparent),
                borderRadius: BorderRadius.circular(10.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(
                  color: Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(10.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(
                  color: Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(10.0),
              ),
              filled: true,
              fillColor:
                  isDarkMode ? Colors.grey.shade900 : Colors.grey.shade300,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            ),
          ),
        ),
        const SizedBox(width: 12.0),
        CircleAvatar(
          backgroundColor: Colors.blueAccent,
          radius: 20.0,
          child: IconButton(
            icon: const Icon(Icons.send, color: Colors.white),
            onPressed: sendMessage,
            iconSize: 24.0,
          ),
        ),
      ],
    );
  }
}
