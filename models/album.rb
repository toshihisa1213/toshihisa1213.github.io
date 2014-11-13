# -* coding: utf-8 -*-

class AlbumGroup < Sequel::Model(:album_groups)
  many_to_one :owner, class:'User'
  one_through_one :event, join_table: :album_group_events
  one_to_many :items, class:'AlbumItem', key: :group_id
  def before_save
    if not self.dummy then
      self.year = if self.start_at.nil? then nil else start_at.year end
    end
  end
  def update_count
    # item_countのupdateは本当はAlbumItemのcreate時だけでいいけど
    # ParanoidBooleanとの都合上update(deleted:true)みたいなことしないといけないので
    # update時にも毎回更新する
    dc = self.items(daily_choose:true).count
    hc = self.items(:comment.not => nil).count
    ic = self.items.count
    tc = self.items(:tag_count.gt => 0).count
    self.update!(daily_choose_count:dc,has_comment_count:hc,item_count:ic,has_tag_count:tc)
  end
end

class AlbumItem < Sequel::Model(:album_items)
  include PatchedItem
  many_to_one :owner, class:'User'
  plugin :serialization, :hourmin, :hourmin
  many_to_one :group, class:'AlbumGroup'

  one_to_one :photo, class:'AlbumPhoto'
  one_to_one :thumb, class:'AlbumThumbnail'
  one_to_many :tags, class:'AlbumTag'

  # TODO
  # 順方向の関連写真
  # has n, :album_relations_r, 'AlbumRelation', child_key: [:source_id]
  # has n, :relations_r, self, through: :album_relations_r, via: :target
  # 逆方向の関連写真
  # has n, :album_relations_l, 'AlbumRelation', child_key: [:target_id]
  # has n, :relations_l, self, through: :album_relations_l, via: :source

  one_to_many :comment_logs, class:'AlbumCommentLog' # コメントの編集履歴

  def validate
    super
    error.add(:rotate,"must be one of 0,90,180,270") unless [0,90,180,270].include?(self.rotate.to_i)
  end

  def before_create
    if self.group_index.nil? then
      ag = self.group
      self.group_index = ag.items.count
    end
  end

  def id_with_thumb
    self.select_attr(:id,:rotate).merge({thumb:self.thumb.select_attr(:id,:width,:height)})
  end

  # 本来 tag_count や tag_names の更新は AlbumTag の :create, :destroy, :save Hookで行うべきだが
  # そうすると AlbumTag を例えば100個更新すると100回 AlbumItem が更新されるので凄く遅くなる．
  # したがって AlbumTag の更新をした後はこの関数を呼ぶという規約にする
  # TODO: 規約に頼らずHookとか使って上記のことを強制する方法
  def do_after_tag_updated
    tag_names = self.tags.map{|x|x.name}.to_json
    self.update!(tag_count:self.tags.count,tag_names:tag_names)
    self.group.update_count
  end
  def after_save
    self.group.update_count
  end

  # 順方向と逆方向の両方の関連写真
  def relations
    self.relations_r + self.relations_l
  end

  # each_revisions_until を使うにはこの関数を実装しておく必要がある
  def patch_syms
    {
      cur_body: :comment,
      last_rev: :comment_revision,
      logs: :comment_logs
    }
  end
end

class AlbumRelation < Sequel::Model(:album_relations)
  many_to_one :source, class:'AlbumItem'
  many_to_one :target, class:'AlbumItem'
  # (source,target) と (target,source) はどちらかしか存在できない
  def after_save
    r = self.class.first(source:self.target, target:self.source)
    if r.nil?.! then r.destroy end
  end
end

class AlbumPhoto < Sequel::Model(:album_photos)
  many_to_one :album_item, class:'AlbumItem'
end
class AlbumThumbnail < Sequel::Model(:album_thumbnails)
  many_to_one :album_item, class:'AlbumItem'
end

class AlbumCommentLog < Sequel::Model(:album_comment_logs)
  many_to_one :album_item
  many_to_one :user
  def after_save
    self.album_item.update!(comment_updated_at:self.created_at)
  end
end

class AlbumTag < Sequel::Model(:album_tags)
  many_to_one :album_item
end

# アルバムと大会の関連
class AlbumGroupEvent < Sequel::Model(:album_group_events)
  many_to_one :album_group
  many_to_one :event
  # event_idやalbum_group_idだけを取ってくるならaggregate使った方が余計なJOINが発生しないで済む
  def self.get_event_id(album_group_id)
    self.aggregate(fields:[:event_id],album_group_id:album_group_id)[0]
  end
  def self.get_album_group_ids(event_id)
    self.aggregate(fields:[:album_group_id],event_id:event_id)
  end
end
