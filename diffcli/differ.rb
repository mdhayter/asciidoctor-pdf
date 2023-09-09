# frozen_string_literal: true

module Asciidoctor
  module Cli
    # Public Invocation class for starting Asciidoctor via CLI
    class Invoker
      include Logging

#      attr_reader :options
#      attr_reader :documents
#      attr_reader :code

      def mark_insert(blk)
        if blk.content_model == :simple
          blk.lines[0].insert(0,'[.insert]##')
          blk.lines.last.insert(-1,'##')
        else
          blk.blocks.each { |b| mark_insert(b)}
        end
      end

      def mark_delete(blk)
        if blk.content_model == :simple
          blk.lines[0].insert(0,'[.delete]##')
          blk.lines.last.insert(-1,'##')
        else
          blk.blocks.each { |b| mark_insert(b)}
        end
      end


      def para_diff(nlines, olines)
        ns = nlines.join(" ")
        os = olines.join(" ")
        puts "diff new: " + ns
        puts "diff old: " + os
        if ns == os
          puts "Equal"
          return 1.0
        end
        if ns.start_with?(os) or ns.end_with?(os)
          puts "app/pre"
          return 0.99
        end
        nwords = ns.split(" ")
        owords = os.split(" ")
        matches = 0.0
        words = 0.0

        until nwords.empty? || owords.empty?
          nw, ow = nwords.shift, owords.shift
          if nw == ow
            matches = matches + 1
            words = words + 1
          else
            if n = owords.index(nw)
              owords.slice!(0, n)
              matches = matches + 1
              words = words + n
            elsif n = nwords.index(ow)
              nwords.slice!(0, n)
              matches = matches + 1
              words = words + n
            else
              words = words + 1
            end
          end
        end
        puts "Gives " + (matches / words).to_s
        return matches / words
      end


      def wordpos(lines)
        res = []

        lines.each_index do |lnum|
          wp = 0
          while wp && wp < lines[lnum].size
            # skip non word
            wp = lines[lnum].index(/[[[:word:]]]+/, wp)
            if wp
              res << [lnum, wp]
              # skip word
              wp = lines[lnum].index(/[^[[:word:]]]+/, wp)
            end
          end
        end
        return res
      end

      def mark_diff(nlines, olines)
        #puts "mark " + nlines[0] + olines[0]


        #nlines[0].insert(0, "[.delete]##" + olines.join(" ") + "##[.insert]##")
        #nlines.last.insert(-1,"##")

        oldwords = olines.join(" ").split(/[^[[:word:]]]+/)
        nl = 0
        added = 0
        nwordpos = wordpos(nlines)
        wpindex = 0
        while wpindex < nwordpos.size-1
          l = nwordpos[wpindex][0]
          if l != nl
            added = 0
            nl = l
          end
          wp = nwordpos[wpindex][1] + added
          newword = nlines[l][wp..][/[[[:word:]]]+/]
          if newword == oldwords[0]
            oldwords.shift
            wpindex += 1
          else
            if ind = oldwords.find_index(newword)
              # the old had more
              delstr = "[.delete]## " + oldwords[0..ind-1].join(" ") + " ## "
              nlines[l].insert(wp, delstr)
              added += delstr.length
              oldwords.shift(ind)
              wpindex += 1
            else
              nlines[l].insert(wp, "[.insert]## ")
              added += 12
              while wpindex < nwordpos.size-1 && newword != oldwords[0]
                wpindex += 1
                l = nwordpos[wpindex][0]
                if l != nl
                  added = 0
                  nl = l
                end
                wp = nwordpos[wpindex][1] + added
                newword = nlines[l][wp..][/[[[:word:]]]+/]
              end
              if wpindex < nwordpos.size-1
                nlines[l].insert(wp, "## ")
                added += 3
              else
                nlines[-1] << (" ## ")
              end
            end
          end
        end
        if oldwords.size > 0
          nlines[-1] << "[.delete]## " + oldwords.join(" ") + " ## "
        end
      end

      def difftree(cur, old)
        unless cur && cur.blocks?
          puts "no cur blocks"
          if old && old.blocks?
            old.find_by(context: :paragraph).each do |para|
              mark_delete(para)
              if cur
                cur.blocks << para
              end
            end
          end
          return
        end
        unless old && old.blocks?
          puts "no old blocks"
          cur.find_by(context: :paragraph).each do |para|
            mark_insert(para)
          end
          return
        end
        old_idx = 0
        cur_idx = 0
        while cur_idx < cur.blocks.length
          puts "scan block " + cur_idx.to_s + " context " + cur.blocks[cur_idx].context.to_s
          if old_idx < old.blocks.length
            puts "   old block " + old_idx.to_s + old.blocks[old_idx].context.to_s
          else
            puts "   no old blocks"
            mark_insert(cur.blocks[cur_idx])
            return
          end
          case cur.blocks[cur_idx].context
          when :paragraph
            cend_idx = cur_idx
            while (cend_idx < cur.blocks.length) && cur.blocks[cend_idx].context == :paragraph
              cend_idx = cend_idx + 1
            end
            #puts "cur has paras to " + cend_idx.to_s
            # cur has paras from cur_idx to cend_idx-1
            oend_idx = old_idx
            while (oend_idx < old.blocks.length) && old.blocks[oend_idx].context == :paragraph
              oend_idx = oend_idx + 1
            end
            # old has paras from old_idx to oend_idx-1
            while cur_idx < cend_idx
              oi = old_idx
              if oi < oend_idx
                pdiff = para_diff(cur.blocks[cur_idx].lines, old.blocks[oi].lines)
              else
                pdiff = 0
              end
              while (pdiff < 0.9) && (oi < oend_idx-1)
                oi = oi + 1
                pdiff = para_diff(cur.blocks[cur_idx].lines, old.blocks[oi].lines)
              end
              if oi == oend_idx-1 && (pdiff < 0.9)
                # did not find a match, new para is new
                puts "New Para at " + cur_idx.to_s
                mark_insert(cur.blocks[cur_idx])
                #mark_diff(cur.blocks[cur_idx].lines, ["no old"])
                cur_idx = cur_idx + 1
              else
                while old_idx < oi
                  puts "Delete Para at " + cur_idx.to_s + " old " + old_idx.to_s
                  # Clone from the cur document to keep other pointers or the converter gets wiggy
                  cur.blocks.insert(cur_idx, cur.blocks[cur_idx].clone)
                  cur.blocks[cur_idx].lines = old.blocks[old_idx].lines
                  mark_delete(cur.blocks[cur_idx])
                  #cur.blocks[cur_idx].lines[0].insert(0, old.blocks[old_idx].lines.join(' '))
                  cur_idx = cur_idx + 1
                  cend_idx = cend_idx + 1
                  old_idx = old_idx + 1
                end
                if (pdiff < 1) && oi < oend_idx
                  mark_diff(cur.blocks[cur_idx].lines, old.blocks[oi].lines)
                end
                cur_idx = cur_idx + 1
                old_idx = oi + 1
              end
            end
          #when :document
          #  # don't expect this?
          #  old_idx = old_idx + 1
          #  cur_idx = cur_idx + 1
          #when :dlist
          #  if old.blocks[old_idx].context == :dlist
          #    #diff_list(nblock, old.block[old_idx])
          #    old_idx = old_idx + 1
          #  else
          #    # was list inserted or something deleted?
          #  end
          when :table
            if old.blocks[old_idx].context == :table
              #diff_table(nblock, old.block[old_idx])
              old_idx = old_idx + 1
              cur_idx = cur_idx + 1
            else
              # was table inserted or something deleted?
              osearch = 1
              found_table = false
              while osearch < 5 && old_idx+osearch < old.blocks.length
                if old.blocks[old_idx+osearch].context == :table
                  found_table = true
                  break
                else
                  osearch += 1
                end
              end
              if found_table
                cur_para = cur_idx - 1
                while cur_para >= 0 && cur.blocks[cur_para].context != :paragraph
                  cur_para -= 1
                end
                # if we don't find a para then the old is lost
                if cur_para >= 0
                  while osearch > 0
                    cur.blocks.insert(cur_idx, cur.blocks[cur_para].clone)
                    cur.blocks[cur_idx].lines = old.blocks[old_idx].lines
                    mark_delete(cur.blocks[cur_idx])
                    cur_idx = cur_idx + 1
                    cend_idx = cend_idx + 1
                    old_idx = old_idx + 1
                    osearch -= 1
                  end
                end
              else
                # mark table as new
                cur_idx = cur_idx + 1
              end
            end
          else
           if old.blocks[old_idx].context == cur.blocks[cur_idx].context
            difftree(cur.blocks[cur_idx], old.blocks[old_idx])
            old_idx = old_idx + 1
            cur_idx = cur_idx + 1
           elsif cur_idx + 1 < cur.blocks.length
            difftree(cur.blocks[cur_idx], nil)
            cur_idx = cur_idx + 1
           else
            difftree(nil, old.blocks[old_idx])
            old_idx = old_idx + 1
           end
          end
        end
      end
    end
  end
end
