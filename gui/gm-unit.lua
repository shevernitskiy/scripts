-- Interface powered (somewhat user friendly) unit editor.
local gui = require 'gui'
local dialog = require 'gui.dialogs'
local widgets =require 'gui.widgets'
local guiScript = require 'gui.script'
local utils = require 'utils'
local args={...}


local target
--TODO: add more ways to guess what unit you want to edit
if args[1]~= nil then
    target=df.units.find(args[1])
else
    target=dfhack.gui.getSelectedUnit(true)
end

if target==nil then
    qerror("No unit to edit") --TODO: better error message
end
local editors={}
function add_editor(editor_class)
    table.insert(editors,{text=editor_class.ATTRS.frame_title,on_submit=function ( unit )
        editor_class{target_unit=unit}:show()
    end})
end
-------------------------------various subeditors---------
--TODO set local sould or better yet skills vector to reduce long skill list access typing
editor_skills=defclass(editor_skills,gui.FramedScreen)
editor_skills.ATTRS={
    frame_style = gui.GREY_LINE_FRAME,
    frame_title = "Skill editor",
    target_unit = DEFAULT_NIL,
    learned_only= false,
}
function list_skills(unit,learned_only)
    local s_=df.job_skill
    local u_skills=unit.status.current_soul.skills
    local ret={}
    for i,v in ipairs(s_) do
        if i>0 then
            local u_skill=utils.binsearch(u_skills,i,"id")
            if u_skill or not learned_only then
                if not u_skill then
                    u_skill={rating=-1,experience=0}
                end

                local rating
                if u_skill.rating >=0 then
                    rating=df.skill_rating.attrs[u_skill.rating]
                else
                    rating={caption="<unlearned>",xp_threshold=0}
                end

                local text=string.format("%s: %s %d %d/%d",df.job_skill.attrs[i].caption,rating.caption,u_skill.rating,u_skill.experience,rating.xp_threshold)
                table.insert(ret,{text=text,id=i})
            end
        end
    end
    return ret
end
function editor_skills:update_list(no_save_place)
    local skill_list=list_skills(self.target_unit,self.learned_only)
    if no_save_place then
        self.subviews.skills:setChoices(skill_list)
    else
        self.subviews.skills:setChoices(skill_list,self.subviews.skills:getSelected())
    end
end
function editor_skills:init( args )
    if self.target_unit.status.current_soul==nil then
        qerror("Unit does not have soul, can't edit skills")
    end

    local skill_list=list_skills(self.target_unit,self.learned_only)

    self:addviews{
    widgets.FilteredList{
        choices=skill_list,
        frame = {t=0, b=1,l=1},
        view_id="skills",
    },
    widgets.Label{
                frame = { b=0,l=1},
                text ={{text= ": exit editor ",
                    key  = "LEAVESCREEN",
                    on_activate= self:callback("dismiss")
                    },
                    {text=": remove level ",
                    key = "SECONDSCROLL_UP",
                    on_activate=self:callback("level_skill",-1)},
                    {text=": add level ",
                    key = "SECONDSCROLL_DOWN",
                    on_activate=self:callback("level_skill",1)}
                    ,
                    {text=": show learned only ",
                    key = "CHANGETAB",
                    on_activate=function ()
                        self.learned_only=not self.learned_only
                        self:update_list(true)
                    end}
                    }
            },
        }
end
function editor_skills:get_cur_skill()
    local list_wid=self.subviews.skills
    local _,choice=list_wid:getSelected()
    if choice==nil then
        qerror("Nothing selected")
    end
    local u_skill=utils.binsearch(self.target_unit.status.current_soul.skills,choice.id,"id")
    return choice,u_skill
end
function editor_skills:level_skill(lvl)
    local sk_en,sk=self:get_cur_skill()
    if lvl >0 then
        local rating

        if sk then
            rating=sk.rating+lvl
        else
            rating=lvl-1
        end

        utils.insert_or_update(self.target_unit.status.current_soul.skills, {new=true, id=sk_en.id, rating=rating}, 'id') --TODO set exp?
    elseif sk and sk.rating==0 and lvl<0 then
        utils.erase_sorted_key(self.target_unit.status.current_soul.skills,sk_en.id,"id")
    elseif sk and lvl<0 then
        utils.insert_or_update(self.target_unit.status.current_soul.skills, {new=true, id=sk_en.id, rating=sk.rating+lvl}, 'id') --TODO set exp?
    end
    self:update_list()
end
function editor_skills:remove_rust(skill)
    --TODO
end
add_editor(editor_skills)
------- counters editor
editor_counters=defclass(editor_counters,gui.FramedScreen)
editor_counters.ATTRS={
    frame_style = gui.GREY_LINE_FRAME,
    frame_title = "Counters editor",
    target_unit = DEFAULT_NIL,
    counters1={
    "think_counter",
    "job_counter",
    "swap_counter",
    "winded",
    "stunned",
    "unconscious",
    "suffocation",
    "webbed",
    "soldier_mood_countdown",
    "soldier_mood", --todo enum,
    "pain",
    "nausea",
    "dizziness",
    },
    counters2={
    "paralysis",
    "numbness",
    "fever",
    "exhaustion",
    "hunger_timer",
    "thirst_timer",
    "sleepiness_timer",
    "stomach_content",
    "stomach_food",
    "vomit_timeout",
    "stored_fat" --TODO what to reset to?
    }
}
function editor_counters:fill_counters()
    local ret={}
    local u=self.target_unit
    for i,v in ipairs(self.counters1) do
        table.insert(ret,{f=u.counters:_field(v),name=v})
    end
    for i,v in ipairs(self.counters2) do
        table.insert(ret,{f=u.counters2:_field(v),name=v})
    end
    return ret
end
function editor_counters:update_counters()
    for i,v in ipairs(self.counter_list) do
        v.text=string.format("%s:%d",v.name,v.f.value)
    end
    self.subviews.counters:setChoices(self.counter_list)
end
function editor_counters:set_cur_counter(value,index,choice)
    choice.f.value=value
    self:update_counters()
end
function editor_counters:choose_cur_counter(index,choice)
    dialog.showInputPrompt(choice.name,"Enter new value:",COLOR_WHITE,
            tostring(choice.f.value),function(new_value)
                self:set_cur_counter(new_value,index,choice)
            end)
end
function editor_counters:init( args )
    if self.target_unit==nil then
        qerror("invalid unit")
    end

    self.counter_list=self:fill_counters()


    self:addviews{
    widgets.FilteredList{
        choices=self.counter_list,
        frame = {t=0, b=1,l=1},
        view_id="counters",
        on_submit=self:callback("choose_cur_counter"),
        on_submit2=self:callback("set_cur_counter",0),--TODO some things need to be set to different defaults
    },
    widgets.Label{
                frame = { b=0,l=1},
                text ={{text= ": exit editor ",
                    key  = "LEAVESCREEN",
                    on_activate= self:callback("dismiss")
                    },
                    {text=": reset counter ",
                    key = "SEC_SELECT",
                    },
                    {text=": set counter ",
                    key = "SELECT",
                    }
                    
                    }
            },
        }
    self:update_counters()
end
add_editor(editor_counters)
-------------------------------main window----------------
unit_editor = defclass(unit_editor, gui.FramedScreen)
unit_editor.ATTRS={
    frame_style = gui.GREY_LINE_FRAME,
    frame_title = "GameMaster's unit editor",
    target_unit = DEFAULT_NIL,
    }


function unit_editor:init(args)

    self:addviews{
    widgets.FilteredList{
        choices=editors,
        on_submit=function (idx,choice)
            if choice.on_submit then
                choice.on_submit(self.target_unit)
            end
        end
    },
    widgets.Label{
                frame = { b=0,l=1},
                text ={{text= ": exit editor",
                    key  = "LEAVESCREEN",
                    on_activate= self:callback("dismiss")
                    },
                    }
            },
        }
end


unit_editor{target_unit=target}:show()
