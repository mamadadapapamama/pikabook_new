import 'package:flutter/material.dart';

class PageIndicatorWidget extends StatelessWidget {
  final int currentPageIndex;
  final int totalPages;
  final Function(int) onPageChanged;

  const PageIndicatorWidget({
    Key? key,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPageChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // 페이지 번호 표시
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${currentPageIndex + 1}/$totalPages 페이지',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              // 이전/다음 페이지 버튼
              if (totalPages > 1)
                Row(
                  children: [
                    // 이전 페이지 버튼
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 16),
                      onPressed: currentPageIndex > 0
                          ? () => onPageChanged(currentPageIndex - 1)
                          : null,
                      color: currentPageIndex > 0 ? Colors.blue : Colors.grey,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
                    // 다음 페이지 버튼
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      onPressed: currentPageIndex < totalPages - 1
                          ? () => onPageChanged(currentPageIndex + 1)
                          : null,
                      color: currentPageIndex < totalPages - 1
                          ? Colors.blue
                          : Colors.grey,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
          // 페이지 인디케이터
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: totalPages,
              itemBuilder: (context, index) {
                final isSelected = index == currentPageIndex;
                return GestureDetector(
                  onTap: () => onPageChanged(index),
                  child: Container(
                    width: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(
                              color: Colors.blue.shade700,
                              width: 2,
                            )
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
