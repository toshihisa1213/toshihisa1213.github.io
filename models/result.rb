# -*- coding: utf-8 -*-

# 大会出場者(後に改名する人がいる可能性があるのと，Userにない人を追加できるようにするため)
class ContestUser
  include ModelBase
  property :name, TrimString, length: 24, required: true,index:true, remove_whitespace: true
  property :user_id, Integer, unique_index: :u1, required: false
  belongs_to :user, required: false
  property :event_id, Integer, unique_index: :u1, required: true
  belongs_to :event
  belongs_to :contest_class

  property :win, Integer, default:0 # 勝ち数(毎回aggregateするのは遅いのでキャッシュ)
  property :lose, Integer, default:0# 負け数(毎回aggregateするのは遅いのでキャッシュ)
  property :point, Integer, default:0 # ポイント(毎回aggregateするのは遅いのでキャッシュ)
  property :point_local, Integer,default:0 # 会内ポイント(毎回aggregateするのは遅いのでキャッシュ)
  property :class_rank, Enum[:a,:b,:c,:d,:e,:f,:g] # ContestClassのclass_rankのキャッシュ

  has 1, :prize, 'ContestPrize'
  has n, :games, 'ContestGame'

  before :save do
    self.class_rank = self.contest_class.class_rank
  end

  after :create do
    ev = self.event
    ev.update(contest_user_count:ev.result_users.count)
  end
end

# 毎回aggregateするのは遅いのでキャッシュ
class ContestResultCache
  include ModelBase
  belongs_to :event
  property :win, Integer, default: 0 # 勝ち数の合計
  property :lose, Integer, default: 0 # 負け数の合計
  property :prizes, Json, default: [] # 入賞情報
  def update_prizes
    ev = self.event
    prz = ev.result_classes.all(order:[:index.asc]).map{|c|
      r = if ev.team_size > 1 then
            c.teams.map{|t|
              if t.prize.nil?.! then
                t.select_attr(:name,:prize).merge({type: :team,class_name:c.class_name})
              end
            }.compact
          else [] end
      r + c.prizes.all(order:[:rank.asc]).map{|x|
        p = x.select_attr(:prize,:point,:point_local,:promotion)
        cuser = x.contest_user
        p.merge!({type: :person,name:cuser.name,user_id:cuser.user_id,class_name:c.class_name})
      }
    }.flatten
    self.update(prizes:prz)
  end
  def update_winlose
    (w,l) = self.event.result_users.aggregate(:win.sum,:lose.sum)
    self.update(win:w,lose:l)
  end
end

# 昇級ランキング用キャッシュ
class ContestPromotionCache
  include ModelBase
  belongs_to :contest_prize, unique: true
  belongs_to :contest_user, unique: true
  property :prize, TrimString, length: 32, required: true # ContestPrizeのprize
  property :class_name, TrimString, length: 16, required: true # ContestClassのclass_name
  property :user_name, TrimString, length: 24, required: true # ConteestUserのname
  belongs_to :event # 昇級した大会
  property :event_date, Date, required:true # Eventのdate
  property :event_name, TrimString, length:48, required:true # Eventのname
  property :debut_date, Date, required:true # 初出場大会もしくは前回昇級してから次の大会の日付
  property :contests, Integer, required: true # 昇級した級の大会出場数
  property :promotion, Enum[:rank_up, :dash, :a_champ], required: true # ContestnPrizeのpromotion
  property :class_rank, Enum[:a,:b,:c,:d,:e,:f,:g], required: true # ContestClassのclass_rank
  property :a_champ_count, Integer # 何回目のA級優勝か 
  validates_absence_of :a_champ_count, if: ->(x){x.promotion != :a_champ }
  validates_presence_of :a_champ_count, if: ->(x){x.promotion == :a_champ }
end

# 大会の各級の情報
class ContestClass
  include ModelBase
  property :event_id, Integer, unique_index: :u1, required: true
  belongs_to :event
  property :class_name, TrimString, length: 16, required: true, unique_index: :u1 # 級の名前
  property :class_rank, Enum[:a,:b,:c,:d,:e,:f,:g] # 実際の級のランク(団体戦や非公認大会の場合はnil)
  property :index, Integer # 順番
  property :num_person, Integer # その級の他の会の人も含む大会自体の全参加人数(個人戦)
  property :round_name, Json, default: {} # 順位決定戦の名前(個人戦), {"4":"順決勝","5":"決勝"} のような形式
  has n, :single_games,'ContestGame' # 試合結果(個人戦)
  has n, :prizes, 'ContestPrize'
  has n, :teams, 'ContestTeam' # 参加チーム(団体戦)
  has n, :users,'ContestUser'
  before :save do
    ev = self.event
    self.class_rank = if ev.official and ev.team_size == 1 then
                        # 公認大会でAからGの文字で始まっていないものは全てA級とみなす
                        Kagetra::Utils.class_from_name(self.class_name) || :a
                      end
  end
end

# 個人賞/入賞
class ContestPrize
  include ModelBase
  property :contest_class_id, Integer, unique_index: :u1, required: true
  belongs_to :contest_class
  property :contest_user_id, Integer, unique_index: :u1, required: true
  belongs_to :contest_user
  property :prize, TrimString, length: 32, required: true, remove_whitespace: true # 実際の名前 (優勝, 全勝賞など)
  property :promotion, Enum[:rank_up, :dash, :a_champ] # 昇級, ダッシュ, A級優勝
  property :point, Integer, default: 0 # A級のポイント
  property :point_local, Integer, default: 0 # 会内ポイント
  property :rank, Integer # 順位(1=優勝, 2=準優勝, 3=三位, 4=四位, ...)
  before :save do
    self.contest_class_id = self.contest_user.contest_class_id
    if self.prize.to_s.empty?.! then
      self.prize = Kagetra::Utils.zenkaku_to_hankaku(self.prize.strip)
      if /\((.+)\)/ =~ self.prize then
        self.promotion = case $1
        when 'ダッシュ' then :dash
        when '昇級' then :rank_up
        end
      end
      if self.prize.start_with?("優勝") and self.contest_class.class_rank == :a then
        self.promotion = :a_champ
      end
      self.rank = Kagetra::Utils.rank_from_prize(self.prize)
    end
  end
  after :save do
    if (self.point || 0) > 0 or (self.point_local || 0) > 0 then
      self.contest_user.update(point:self.point,point_local:self.point_local)
    end
    self.contest_class.event.update_cache_prizes
    if [:rank_up,:a_champ].include?(self.promotion) then
      self.save_promotion_cache
    end
  end
  def save_promotion_cache
    event = self.contest_class.event
    user_name = self.contest_user.name
    contest_users = ContestUser.all(name:user_name)
    promotions = ContestPrize.all(contest_user_id:contest_users.map{|x|x.id},promotion: :rank_up)
    prev_promotion = promotions.map{|x|x.contest_class.event}.select{|x|x.date < event.date}.sort_by{|x|x.date}.last
    cond = if prev_promotion.nil? then {} else {:date.gt => prev_promotion.date} end
    debut_date = Event.all(cond.merge(id:contest_users.map{|x|x.event_id},kind: :contest,order: [:date.asc])).first.date

    # 東京都大会のように非公認大会であっても昇級できる大会もあるのでその分を考慮
    contests = Event.all(id:contest_users.map{|x|x.event_id},kind: :contest,official:true,team_size:1,:date.gte => debut_date, :date.lt => event.date).count + 1
    class_rank = self.contest_class.class_rank || Kagetra::Utils.class_from_name(self.contest_class.class_name)

    a_champ_count = if self.promotion == :a_champ then
      ContestPrize.all(contest_user_id:contest_users.map{|x|x.id},promotion: :a_champ).map{|x|x.contest_class.event}.select{|x|x.date < event.date}.size + 1
    end

    data = {
      contest_user_id: self.contest_user_id,
      prize: self.prize.sub(/\(.*\)/,""),
      class_name: self.contest_class.class_name,
      user_name: user_name,
      event_id: event.id,
      event_name: event.name,
      event_date: event.date,
      contests: contests,
      debut_date: debut_date,
      promotion: self.promotion,
      class_rank: class_rank,
      a_champ_count: a_champ_count
    }
    Kagetra::Utils.dm_debug{
      ContestPromotionCache.update_or_create({contest_prize_id:self.id},data)
    }
  end
end


# 試合結果(個人戦, 団体戦共通)
class ContestGame
  include ModelBase
  property :event_id, Integer, index:true, allow_nil: false # 検索用にキャッシュ
  belongs_to :event
  # Discriminator を使った Single Table Inheritance は子クラスにインデックスを作れないし
  # 親クラスと子クラスの間のunique_indexを作れないので自分で切り変える
  property :type, Enum[:single,:team] , index: true # 個人戦, 団体戦
  # belongs_to does not support unique_index so we do this ugly hack.
  property :contest_user_id, Integer, unique_index: [:u1], required: true
  belongs_to :contest_user
  property :result, Enum[:now,:win,:lose,:default_win], required: true # 勝敗 => 対戦中, 勝ち, 負け, 不戦勝,
  property :score_str, TrimString, length: 8 # 枚数(文字) "棄" とか "3+1" とかあるので文字列として用意しておく
  property :score_int, Integer, index: true # 枚数(数字), score_str を parse したもの．集計する際に利用
  property :opponent_name, TrimString, length: 24, index:true, remove_whitespace: true # 対戦相手の名前
  property :opponent_belongs, TrimString, length: 36, remove_whitespace: true # 対戦相手の所属, 個人戦のみ使用 (ただし団体戦の大会でも対戦相手の所属がバラバラな場合はここに書く))
  property :comment, TrimText # コメント

  is_single = ->(x){ x.type == :single }
  is_team = ->(x){ x.type == :team }

  # 個人戦用
  property :contest_class_id, Integer, unique_index: :u1, index: true
  belongs_to :contest_class
  property :round, Integer, unique_index: :u1

  # required:true の代わりに条件付きvalidationする(required:trueだとDBにNOT NULLを付けてしまう)
  validates_presence_of :contest_class_id, if: is_single
  validates_presence_of :round, if: is_single
  validates_absence_of :contest_team_opponent_id, if: is_single
  validates_absence_of :opponent_order, if: is_single

  # 団体戦用
  property :contest_team_opponent_id, Integer, index: true
  belongs_to :contest_team_opponent
  property :opponent_order, Integer # 将順

  validates_presence_of :contest_team_opponent_id, if: is_team
  validates_absence_of :contest_class_id, if: is_team
  validates_absence_of :round, if: is_team

  before :save do
    if is_single.call(self) then
      self.contest_class_id = self.contest_user.contest_class_id
    end
    self.event = self.contest_user.event if self.event.nil?
    self.score_int = Kagetra::Utils.eval_score_char(self.score_str)
  end

  # TODO: 複数の勝ち負けの一括更新に対応
  after :save do
    # 本来なら下記の処理はupdate_or_createしか呼んでないので不要なはずだが，何らかの条件下で同じものが出来てしまう模様
    # したがってそれが起きてしまった場合はソフトウェア的にunique処理を行う
    # TODO: 既にDBに存在してしまった以下のunique条件を満たさないデータを削除する
    # TODO: unique条件を満たさないデータが出来てしまう原因を見つけ以下の処理を不要にする．
    # TODO: 個人戦と団体戦でテーブルを分け，それぞれに unique index を作る
    if is_single.call(self) then
      # event_id, contest_user_id, contest_class_id, round で unique にする
      self.class.all(self.select_attr(:event_id,:contest_user_id,:contest_class_id,:round).merge({:id.not => self.id})).destroy!
    elsif is_team.call(self) then
      # event_id, contest_user_id, contest_team_opponent_id で unique にする
      self.class.all(self.select_attr(:event_id,:contest_user_id,:contest_team_opponent_id).merge({:id.not => self.id})).destroy!
    end

    u = self.contest_user
    updates = Hash[[:win,:lose].map{|sym|
      [sym,u.games(result:sym).count]
    }]
    u.update(updates)
    u.event.update_cache_winlose
  end
end

# 誰がどのチームの何将か(団体戦)
class ContestTeamMember
  include ModelBase
  # belongs_to does not support unique_index so we do this ugly hack.
  property :contest_user_id, Integer, unique_index: :u1, required: true
  belongs_to :contest_user
  property :contest_team_id, Integer, unique_index: :u1, required: true
  belongs_to :contest_team
  property :order_num, Integer, required: true # 将順
end

# どのチームがどの級に出場しているか(団体戦)
class ContestTeam
  include ModelBase
  # belongs_to does not support unique_index so we do this ugly hack.
  property :contest_class_id, Integer, unique_index: :u1, required: true
  belongs_to :contest_class
  property :name, TrimString, length: 48, unique_index: :u1, required: true # チーム名
  property :prize, TrimString, length: 24 # チーム入賞
  property :rank, Integer # チーム入賞から推定した順位
  property :promotion, Enum[:rank_up,:rank_down] # 昇級, 陥落
  has n, :members, 'ContestTeamMember'
  has n, :opponents, 'ContestTeamOpponent'
  before :save do
    if self.prize.to_s.empty?.! then
      self.prize = Kagetra::Utils.zenkaku_to_hankaku(self.prize.strip)
      if /\((.+)\)/ =~ self.prize then
        self.promotion = case $1
        when '昇級' then :rank_up
        when '陥落' then :rank_down
        end
      end
      self.rank = Kagetra::Utils.rank_from_prize(self.prize)
    end
  end
  after :save do
    self.contest_class.event.update_cache_prizes
  end
end

# 各チームが何回戦にどのチームと対戦したか(団体戦)
class ContestTeamOpponent
  include ModelBase
  property :contest_team_id, Integer, unique_index: :u1, required: true
  belongs_to :contest_team
  property :name, TrimString, length: 48 # 対戦相手のチーム名
  property :round, Integer, unique_index: :u1, required: true # n回戦
  property :round_name, TrimString, length: 36 # 決勝, 順位決定戦など
  property :kind, Enum[:team, :single], required: true # 団体戦, 個人戦 (大会としては団体戦だけど各自が別々のチーム相手に対戦)
  has n, :games, 'ContestGame' # 試合結果(団体戦)
  validates_absence_of :name, if: ->(x){x.kind == :single}
end
