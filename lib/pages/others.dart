import 'package:flutter/material.dart';

class Others extends StatefulWidget {
  const Others({super.key});

  @override
  State<Others> createState() => _OthersState();
}

//TODO : Create actual convo db
class _OthersState extends State<Others> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _dummyConversations.length,
              itemBuilder: (context, index) {
                final conversation = _dummyConversations[index];
                return DMListItem(conversation: conversation);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DMListItem extends StatelessWidget {
  final DMConversation conversation;

  const DMListItem({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        // TODO: Open convo
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: conversation.profileColor,
                  child: Text(
                    conversation.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (conversation.isOnline)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        conversation.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: conversation.isUnread ? FontWeight.bold : FontWeight.normal,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          if (conversation.isDelivered)
                            Icon(
                              conversation.isSeen ? Icons.done_all : Icons.done,
                              size: 16,
                              color: conversation.isSeen ? Colors.blue : Colors.grey,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            conversation.timestamp,
                            style: TextStyle(
                              fontSize: 12,
                              color: conversation.isUnread ? Colors.white : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: conversation.isUnread ? Colors.white : Colors.grey,
                            fontWeight: conversation.isUnread ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.isUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DMConversation {
  final String name;
  final String lastMessage;
  final String timestamp;
  final bool isUnread;
  final bool isOnline;
  final bool isDelivered;
  final bool isSeen;
  final Color profileColor;

  DMConversation({
    required this.name,
    required this.lastMessage,
    required this.timestamp,
    this.isUnread = false,
    this.isOnline = false,
    this.isDelivered = false,
    this.isSeen = false,
    required this.profileColor,
  });
}

final List<DMConversation> _dummyConversations = [
  DMConversation(
    name: 'abg',
    lastMessage: 'u can tap',
    timestamp: '2m',
    isUnread: true,
    isOnline: true,
    profileColor: Colors.purple,
  ),
  DMConversation(
    name: 'abhi',
    lastMessage: 'i am a good boy',
    timestamp: '2m',
    isUnread: true,
    isOnline: true,
    profileColor: Colors.purple,
  ),
  DMConversation(
    name: 'joseph',
    lastMessage: 'karpathy talk??',
    timestamp: '15m',
    isDelivered: true,
    isSeen: true,
    profileColor: Colors.blue,
  ),
  DMConversation(
    name: 'Emma Wilson',
    lastMessage: 'heyyy',
    timestamp: '1h',
    isUnread: true,
    profileColor: Colors.pink,
  ),
  DMConversation(
    name: 'Alex Rodriguez',
    lastMessage: 'chess match tmrw?',
    timestamp: '3h',
    isDelivered: true,
    isSeen: false,
    isOnline: true,
    profileColor: Colors.orange,
  ),
  DMConversation(
    name: 'Jessica Taylor',
    lastMessage: 'send me linkedin',
    timestamp: '1d',
    profileColor: Colors.green,
  ),
  DMConversation(
    name: 'David Kim',
    lastMessage: 'hey bro',
    timestamp: '2d',
    isOnline: true,
    profileColor: Colors.indigo,
  ),
  DMConversation(
    name: 'Lisa Anderson',
    lastMessage: 'shut up',
    timestamp: '3d',
    profileColor: Colors.teal,
  ),
  DMConversation(
    name: 'Ryan Martinez',
    lastMessage: 'u are a good boy',
    timestamp: '1w',
    profileColor: Colors.deepOrange,
  ),
  DMConversation(
    name: 'Sophie Brown',
    lastMessage: 'im homosexual',
    timestamp: '1w',
    isUnread: true,
    profileColor: Colors.cyan,
  ),
  DMConversation(
    name: 'Tom Wilson',
    lastMessage: 'idk',
    timestamp: '2w',
    isDelivered: true,
    isSeen: true,
    profileColor: Colors.amber,
  ),
];