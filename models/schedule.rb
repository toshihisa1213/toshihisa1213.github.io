# -*- coding: utf-8 -*-

# 予定表の祝日の情報
class ScheduleDateInfo
  include ModelBase
  property :date, Date, unique: true, required: true
  property :names, Json, default: []
  property :holiday, Boolean, default: false # 休日かどうか
end

# 予定表のアイテム
class ScheduleItem
  include ModelBase
  property :date, Date, index: true, required: true # 日付
  property :kind, Enum[:practice, :party, :etc], default: :etc #練習, コンパ, その他
  property :public, Boolean, default: true # 公開されているか
  property :emphasis, Flag[:name, :start_at, :end_at, :place]  # 強調表示 => 名前, 開始時刻, 終了時刻, 場所
  property :name, TrimString, length: 48, required: true
  property :start_at, HourMin # 開始時刻
  property :end_at, HourMin # 終了時刻
  property :place, TrimString, length: 48 # 場所
  property :description, TrimText # 説明
  belongs_to :owner, 'User' # 所有者
end
