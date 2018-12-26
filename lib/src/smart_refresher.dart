/*
    Author: Jpeng
    Email: peng8350@gmail.com
    createTime:2018-05-01 11:39
 */

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'internals/default_constants.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:pull_to_refresh/src/internals/indicator_config.dart';
import 'package:pull_to_refresh/src/internals/indicator_wrap.dart';
import 'package:pull_to_refresh/src/internals/refresh_physics.dart';
import 'indicator/classic_indicator.dart';
import 'dart:math' as math;

enum WrapperType { Refresh, Loading }

class RefreshStatus {
  static const int idle = 0;
  static const int canRefresh = 1;
  static const int refreshing = 2;
  static const int completed = 3;
  static const int failed = 4;
  static const int noMore = 5;
}

/*
    This is the most important component that provides drop-down refresh and up loading.
 */
class SmartRefresher extends StatefulWidget {
  //indicate your listView
  final ScrollView child;

  final IndicatorBuilder headerBuilder;
  final IndicatorBuilder footerBuilder;
  // configure your header and footer
  final Config headerConfig, footerConfig;
  // This bool will affect whether or not to have the function of drop-up load.
  final bool enablePullUp;
  //This bool will affect whether or not to have the function of drop-down refresh.
  final bool enablePullDown;
  // if open OverScroll if you use RefreshIndicator and LoadFooter
  final bool enableOverScroll;
  // upper and downer callback when you drag out of the distance
  final OnRefresh onRefresh;
  final OnLoad onLoad;
  // This method will callback when the indicator changes from edge to edge.
  final OnOffsetChange onOffsetChange;
  //controll inner state
  final RefreshController controller;
  final bool autoRefresh;
  final bool autoLoad;
  final int pageIndex;
  final int pageSize;
  SmartRefresher(
      {Key key,
      @required this.child,
      IndicatorBuilder headerBuilder,
      IndicatorBuilder footerBuilder,
      RefreshController controller,
      this.headerConfig: const RefreshConfig(),
      this.footerConfig: const LoadConfig(),
      this.enableOverScroll: default_enableOverScroll,
      this.enablePullDown: default_enablePullDown,
      this.enablePullUp: default_enablePullUp,
      this.onRefresh,
      this.onLoad,
      this.onOffsetChange,
      this.autoRefresh = true,
      this.autoLoad = true,
      this.pageIndex = 0,
      this.pageSize = 20})
      : assert(child != null),
        controller = controller ?? new RefreshController(),
        this.headerBuilder = headerBuilder ??
            ((BuildContext context, int mode) {
              return new ClassicIndicator(mode: mode);
            }),
        this.footerBuilder = footerBuilder ??
            ((BuildContext context, int mode) {
              return new ClassicIndicator(mode: mode);
            }),
        super(key: key);

  @override
  _SmartRefresherState createState() => new _SmartRefresherState();
}

class _SmartRefresherState extends State<SmartRefresher> {
  // listen the listen offset or on...
  ScrollController _scrollController;
  // the bool will check the user if dragging on the screen.
  bool _isDragging = false;
  // key to get height header of footer
  final GlobalKey _headerKey = new GlobalKey(), _footerKey = new GlobalKey();
  // the height must be  equals your headerBuilder
  double _headerHeight = 0.0, _footerHeight = 0.0;

  ValueNotifier<double> offsetLis = new ValueNotifier(0.0);

  ValueNotifier<int> topModeLis = new ValueNotifier(0);

  ValueNotifier<int> bottomModeLis = new ValueNotifier(0);

  Page _page;
  //handle the scrollStartEvent
  bool _handleScrollStart(ScrollStartNotification notification) {
    // This is used to interupt useless callback when the pull up load rolls back.
    if ((notification.metrics.outOfRange)) {
      return false;
    }
    GestureProcessor topWrap = _headerKey.currentState as GestureProcessor;
    GestureProcessor bottomWrap = _footerKey.currentState as GestureProcessor;
    if (widget.enablePullUp) bottomWrap.onDragStart(notification);
    if (widget.enablePullDown) topWrap.onDragStart(notification);
    return false;
  }

  //handle the scrollMoveEvent
  bool _handleScrollMoving(ScrollUpdateNotification notification) {
    if (_measure(notification) != -1.0)
      offsetLis.value = _measure(notification);
    GestureProcessor topWrap = _headerKey.currentState as GestureProcessor;
    GestureProcessor bottomWrap = _footerKey.currentState as GestureProcessor;
    if (widget.enablePullUp) bottomWrap.onDragMove(notification);
    if (widget.enablePullDown) topWrap.onDragMove(notification);
    return false;
  }

  //handle the scrollEndEvent
  bool _handleScrollEnd(ScrollNotification notification) {
    GestureProcessor topWrap = _headerKey.currentState as GestureProcessor;
    GestureProcessor bottomWrap = _footerKey.currentState as GestureProcessor;
    if (widget.enablePullUp) bottomWrap.onDragEnd(notification);
    if (widget.enablePullDown) topWrap.onDragEnd(notification);
    return false;
  }

  bool _dispatchScrollEvent(ScrollNotification notification) {
    // when is scroll in the ScrollInside,nothing to do
    if ((!_isPullUp(notification) && !_isPullDown(notification))) return false;
    if (notification is ScrollStartNotification) {
      return _handleScrollStart(notification);
    }
    if (notification is ScrollUpdateNotification) {
      //if dragDetails is null,This represents the user's finger out of the screen
      if (notification.dragDetails == null) {
        return _handleScrollEnd(notification);
      } else if (notification.dragDetails != null) {
        return _handleScrollMoving(notification);
      }
    }
    if (notification is ScrollEndNotification) {
      _handleScrollEnd(notification);
    }

    return false;
  }

  //check user is pulling up
  bool _isPullUp(ScrollNotification noti) {
    return noti.metrics.pixels < 0;
  }

  //check user is pulling down
  bool _isPullDown(ScrollNotification noti) {
    return noti.metrics.pixels > 0;
  }

  double _measure(ScrollNotification notification) {
    if (notification.metrics.minScrollExtent - notification.metrics.pixels >
        0) {
      return (notification.metrics.minScrollExtent -
              notification.metrics.pixels) /
          widget.headerConfig.triggerDistance;
    } else if (notification.metrics.pixels -
            notification.metrics.maxScrollExtent >
        0) {
      return (notification.metrics.pixels -
              notification.metrics.maxScrollExtent) /
          widget.footerConfig.triggerDistance;
    }
    return -1.0;
  }

  void _init() {
    _scrollController = new ScrollController();
    widget.controller.scrollController = _scrollController;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _onAfterBuild();
    });
    _scrollController.addListener(_handleOffsetCallback);
    widget.controller._headerMode = topModeLis;
    widget.controller._footerMode = bottomModeLis;

    _page = Page();
    _page.index = widget.pageIndex;
    _page.size = widget.pageSize;

    widget.controller._page = _page;
    if (widget.autoRefresh) {
      topModeLis.value=RefreshStatus.refreshing;
      widget.onRefresh();
    } else if (widget.autoLoad) {
      bottomModeLis.value=RefreshStatus.refreshing;
      widget.onLoad(_page);
    }
  }

  void _handleOffsetCallback() {
    final double overscrollPastStart = math.max(
        _scrollController.position.minScrollExtent -
            _scrollController.position.pixels +
            (widget.headerConfig is RefreshConfig &&
                    (topModeLis.value == RefreshStatus.refreshing ||
                        topModeLis.value == RefreshStatus.completed ||
                        topModeLis.value == RefreshStatus.failed)
                ? (widget.headerConfig as RefreshConfig).visibleRange
                : 0.0),
        0.0);
    final double overscrollPastEnd = math.max(
        _scrollController.position.pixels -
            _scrollController.position.maxScrollExtent +
            (widget.footerConfig is RefreshConfig &&
                    (bottomModeLis.value == RefreshStatus.refreshing ||
                        bottomModeLis.value == RefreshStatus.completed ||
                        bottomModeLis.value == RefreshStatus.failed)
                ? (widget.footerConfig as RefreshConfig).visibleRange
                : 0.0),
        0.0);
    if (overscrollPastStart > overscrollPastEnd) {
      if (widget.headerConfig is RefreshConfig) {
        if (widget.onOffsetChange != null) {
          widget.onOffsetChange(true, overscrollPastStart);
        }
      } else {
        if (widget.onOffsetChange != null) {
          widget.onOffsetChange(true, overscrollPastStart);
        }
      }
    } else if (overscrollPastEnd > 0) {
      if (widget.footerConfig is RefreshConfig) {
        if (widget.onOffsetChange != null) {
          widget.onOffsetChange(false, overscrollPastEnd);
        }
      } else {
        if (widget.onOffsetChange != null) {
          widget.onOffsetChange(false, overscrollPastEnd);
        }
      }
    }
  }

  _didChangeMode(bool up, ValueNotifier<int> mode) {
    switch (mode.value) {
      case RefreshStatus.refreshing:
        if (up && widget.onRefresh != null) {
          _page.index = 1;
          widget.onRefresh();
        } else if (widget.onLoad != null) {
          _page.index++;
          widget.onLoad(_page);
        }
        if (up && widget.headerConfig is RefreshConfig) {
          RefreshConfig config = widget.headerConfig as RefreshConfig;
          _scrollController
              .jumpTo(_scrollController.offset + config.visibleRange);
        }
        break;
    }
  }

  void _onAfterBuild() {
    if (widget.headerConfig is LoadConfig) {
      if ((widget.headerConfig as LoadConfig).bottomWhenBuild) {
        _scrollController.jumpTo(-(_scrollController.position.pixels -
            _scrollController.position.maxScrollExtent));
      }
    }

    topModeLis.addListener(() {
      _didChangeMode(true, topModeLis);
    });
    bottomModeLis.addListener(() {
      _didChangeMode(false, bottomModeLis);
    });
    setState(() {
      if (widget.enablePullDown)
        _headerHeight = _headerKey.currentContext.size.height;
      if (widget.enablePullUp) {
        _footerHeight = _footerKey.currentContext.size.height;
      }
    });
  }

  @override
  void dispose() {
    // TODO: implement dispose
    _scrollController.removeListener(_handleOffsetCallback);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _init();
  }

  Widget _buildWrapperByConfig(Config config, bool up) {
    if (config is LoadConfig) {
      return new LoadWrapper(
        key: up ? _headerKey : _footerKey,
        modeListener: up ? topModeLis : bottomModeLis,
        up: up,
        autoLoad: config.autoLoad,
        triggerDistance: config.triggerDistance,
        builder: up ? widget.headerBuilder : widget.footerBuilder,
      );
    } else if (config is RefreshConfig) {
      return new RefreshWrapper(
        key: up ? _headerKey : _footerKey,
        modeLis: up ? topModeLis : bottomModeLis,
        up: up,
        onOffsetChange: (bool up, double offset) {
          if (widget.onOffsetChange != null) {
            widget.onOffsetChange(
                up,
                up
                    ? -_scrollController.offset + offset
                    : _scrollController.position.pixels -
                        _scrollController.position.maxScrollExtent +
                        offset);
          }
        },
        completeDuration: config.completeDuration,
        triggerDistance: config.triggerDistance,
        visibleRange: config.visibleRange,
        builder: up ? widget.headerBuilder : widget.footerBuilder,
      );
    }
    return new Container();
  }

  @override
  void didUpdateWidget(SmartRefresher oldWidget) {
    // TODO: implement didUpdateWidget
    widget.controller._headerMode = topModeLis;
    widget.controller._footerMode = bottomModeLis;
    widget.controller.scrollController = _scrollController;
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> slivers =
        new List.from(widget.child.buildSlivers(context), growable: true);
    slivers.add(new SliverToBoxAdapter(
      child: widget.footerBuilder != null && widget.enablePullUp
          ? _buildWrapperByConfig(widget.footerConfig, false)
          : new Container(),
    ));
    slivers.insert(
        0,
        new SliverToBoxAdapter(
            child: widget.headerBuilder != null && widget.enablePullDown
                ? _buildWrapperByConfig(widget.headerConfig, true)
                : new Container()));
    return new LayoutBuilder(builder: (context, cons) {
      return new Stack(
        children: <Widget>[
          new Positioned(
              top: !widget.enablePullDown || widget.headerConfig is LoadConfig
                  ? 0.0
                  : -_headerHeight,
              bottom: !widget.enablePullUp || widget.footerConfig is LoadConfig
                  ? 0.0
                  : -_footerHeight,
              left: 0.0,
              right: 0.0,
              child: new NotificationListener(
                child: new CustomScrollView(
                  physics: new RefreshScrollPhysics(
                      enableOverScroll: widget.enableOverScroll),
                  controller: _scrollController,
                  slivers: slivers,
                ),
                onNotification: _dispatchScrollEvent,
              )),
        ],
      );
    });
  }
}

abstract class Indicator extends StatefulWidget {
  final int mode;

  const Indicator({Key key, this.mode}) : super(key: key);
}

class RefreshController {
  ValueNotifier<int> _headerMode;
  ValueNotifier<int> _footerMode;
  Page _page;

  ScrollController scrollController;

  void requestRefresh(bool up) {
    if (up) {
      scrollController.jumpTo(-60);
      if (_headerMode.value == RefreshStatus.idle)
        _headerMode.value = RefreshStatus.refreshing;
    } else {
      if (_footerMode.value == RefreshStatus.idle) {
        _footerMode.value = RefreshStatus.refreshing;
      }
    }
  }

  void scrollTo(double offset) {
    scrollController.jumpTo(offset);
  }

  void sendBack(bool up, int mode) {
    if (up) {
      // scrollController.jumpTo(
      //               scrollController.offset);
      _headerMode.value = mode;
    } else {
      _footerMode.value = mode;
    }
  }

  ///不填写参数则更新下拉状态
  ///dataSize当前页数据量 控制是否可以继续下拉还是现实end
  ///hasNext是否有下一页 控制是否可以继续下拉还是现实end
  void endSuccess({
    int dataSize,
    bool hasNext,
  }) {
    if (dataSize == null && hasNext == null) {
      _headerMode.value = RefreshStatus.completed;
      _footerMode.value = RefreshStatus.idle;
    } else if (!hasNext || dataSize < _page.size) {
      _footerMode.value = RefreshStatus.noMore;
    } else {
      _footerMode.value = RefreshStatus.completed;
    }
  }

  ///dataSize : 当前页获取的数据总数(注意是当前页)
  ///totalPage : 列表的总页数
  void endByPage({
    int dataSize,
    int totalPage,
  }) {
    if (dataSize == null && totalPage == null) {
      _headerMode.value = RefreshStatus.idle;
    } else if (totalPage == _page.index + 1 || dataSize < _page.size) {
      _footerMode.value = RefreshStatus.noMore;
    } else {
      _footerMode.value = RefreshStatus.idle;
    }
  }

  ///dataSize : 当前页获取的数据总数(注意是当前页)
  ///totalSize : 列表的总数据量

  void endBySize({
    int dataSize,
    int totalSize,
  }) {
    if (dataSize == null && totalSize == null) {
      _headerMode.value = RefreshStatus.idle;
    } else if (totalSize <= (_page.index + 1) * _page.size ||
        dataSize < _page.size) {
      _footerMode.value = RefreshStatus.noMore;
    } else {
      _footerMode.value = RefreshStatus.idle;
    }
  }

  ///隐藏下拉刷新和上拉加载的状态, 在联网获取数据失败后调用;
  void endErr() {
    if (_page.index != 0) {
      _page.index--;
    }
    _footerMode.value = RefreshStatus.failed;
    _headerMode.value = RefreshStatus.failed;
  }

  ///主动触发下拉刷新
  void triggerDownScroll() {
    // scrollController.jumpTo(-60);
    if (_headerMode.value == RefreshStatus.idle)
    {
      _page.index=0;
      _headerMode.value = RefreshStatus.refreshing;
    }
  }

  ///主动触发上拉加载
  void triggerUpScroll() {
    print("triggerUpScroll");
    // scrollController.jumpTo(9999);
    if (_footerMode.value == RefreshStatus.idle) {
       _page.index++;
      _footerMode.value = RefreshStatus.refreshing;
    }
  }

  int get headerMode => _headerMode.value;

  int get footerMode => _footerMode.value;

  isRefresh(bool up) {
    if (up) {
      return _headerMode.value == RefreshStatus.refreshing;
    } else {
      return _footerMode.value == RefreshStatus.refreshing;
    }
  }
}
