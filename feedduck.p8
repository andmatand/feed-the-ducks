pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
fps = 30

-- button library
buttons = {}
for i = 0, 5 do
  buttons[i] = {
    down = false
  }
end
function update_buttons()
  for i, b in pairs(buttons) do
    if btn(i) then
      if not b.down then
        b.down = true

        -- call the btn_pushed callback when a button is first pushed
        btn_pushed(i)
      end
    else
      b.down = false
    end
  end
end

function create_timer(frames)
  return {
    length = frames,
    value = frames,
    reset = function(self)
      self.value = self.length
    end,
    update = function(self)
      if self.value > 1 then
        self.value -= 1
      else
        return true
      end
    end
  }
end

-- center print
function cprint(s, x, y)
  print(s, x - (((#s * 4) - 1) / 2), y)
end

function shallow_copy(t)
  local t2 = {}
  for k, v in pairs(t) do
    t2[k] = v
  end
  return t2
end


-- the easing functions below are adapted from
-- https://github.com/emmanueloga/easing
-- see the "licence" file in this repo for details
function ease_out_cubic(t, b, c, d)
  t = t / d - 1
  return c * ((t ^ 3) + 1) + b
end
function ease_in_cubic(t, b, c, d)
  t = t / d
  return c * (t ^ 3) + b
end


function game1()
  function game1_init()
    -- switch to 64x64 mode
    poke(0x5f2c, 3)

    gamestate = nil
    camx = 64
    camy = -32

    -- define constants
    screen_w = 64
    max_velocity_x = 1
    max_velocity_y = 5
    default_gravity = .32

    -- find ponds on the map
    ponds = {}
    find_ponds()

    actors = {}
    foods = {}

    -- create boatduck
    boatduck = create_actor({
      anims = {
        default = create_anim({8}, 0),
        chomp = create_anim({9, 10, 9}, 8)
      },
      canswim = true,
      pond = ponds[1],
      drawh = 4,
      gravity = 0,
      maxvx = .4,
      feetoffsets = {1, 6}
    })

    -- don't let boatduck go outside the pond
    boatduck.minx = ponds[1].x1 - 1
    boatduck.maxx = (ponds[1].x2 - boatduck.draww) + 2

    -- create fatduck
    fatduck = create_actor({
      anims = {
        default = create_anim({8}, 0),
        chomp = create_anim({9, 10, 9}, 8)
      },
      drawh = 4,
      gravity = 0,
      palette = {{4, 5}},
      feetoffsets = {1, 6},
      canswim = true,
      state = 'wait'
    })

    -- create goose
    goose = create_actor({
      anims = {
        default = create_anim({11}, 0),
        walk = create_anim({11, 13, 12, 14}, 3, true)
      },
      drawh = 10,
      spriteh = 11,
      bottomoffset = 10,
      feetoffsets = {1, 7},
      state = 'wait',
      gravity = 0,
      minteleportx = 0
    })

    -- create kitty
    kitty = create_actor({
      anims = {
        default = create_anim({1}, 0),
        jump = create_anim({5}, 0),
        land = create_anim({6}, 8),
        crouch = create_anim({6}, 0),
        walk = create_anim({4, 1}, 4, true),
        landwalk = create_anim({24, 6}, 4),
        turn = create_anim({7}, 8, true)
      },
      draww = 6,
      drawh = 5,
      dir = 1,
      xhit = {
        offset = 2,
        w = 5,
      },
      flipoffset = 2,
      feetoffsets = {3, 6}
    })

    -- set positions of things based on map data
    checkpoints = {}
    find_things_on_map()

    items = {{
      x = 8,
      y = 40,
      sprite = 36
    }}

    local corn = items[1]
    corn.box = {
      x1 = corn.x,
      y1 = corn.y + 2,
      x2 = corn.x + 5,
      y2 = corn.y + 7
    }


    -- create spring-platform groups
    springplatforms = {}

    boatduck.spring = create_spring_platform(
      boatduck,
      {
        {offset = {x = 3, y = 2}, w = 5}
      }
    )
    add(springplatforms, boatduck.spring)

    fatduck.spring = create_spring_platform(
      fatduck,
      {
        head = {offset = {x = 1, y = 4}, w = 2},
        bill = {offset = {x = 0, y = 3}, w = 2},
        back = {offset = {x = 3, y = 2}, w = 5}
      }
    )
    add(springplatforms, fatduck.spring)


    act2title = {
      text = 'where is goose?',
      x = 3,
      y = 40
    }

    player = kitty

    -- initialize spring platform box caches
    for sp in all(springplatforms) do
      sp:update_platform_boxes()
    end

    -- disable fatduck's head and bill spring platforms
    fatduck.spring.disabled_platforms = {
      head = fatduck.spring.platforms.head,
      bill = fatduck.spring.platforms.bill
    }
    fatduck.spring.platforms.head = nil
    fatduck.spring.platforms.bill = nil

    update_act2_title_cr = cocreate(update_act2_title)
  end

  function _update()
    update_buttons()
    if player.isenabled then
      process_player_input()
    end

    remove_expired_foods()
    update_ponds()
    update_npcs()

    pre_update_spring_platforms()

    update_actors()
    save_checkpoint(kitty)
    update_spring_platforms()
    update_items()

    if gamestate == 'act2 title' then
      coresume(update_act2_title_cr)
    end

    post_update_actors()

    update_camera()
  end

  function _draw()
    cls()
    camera(camx, camy)

    -- draw background tiles
    map(0, 0, 0, 0, 128, 8, 128)

    if gamestate == 'act2 title' then
      draw_act2_title()
    end
    
    draw_items()
    draw_actors()
    draw_ponds()
    draw_foods()

    -- draw foreground land
    map(0, 0, 0, 0, 128, 8, 1)

    if gamestate == 'act2 title' then
      fade_act2_title_bg()
    elseif gamestate == 'credits' then
      color(7)
      cprint('thanks for', 96, 6)
      cprint('playing', 96, 12)

      cprint('feed the ducks', 160, 4)
      cprint('by andrew', 160, 16)
      cprint('vector art by', 160, 28)
      cprint('aubrianne', 160, 34)
    end
  end

  function draw_act2_title()
    print(act2title.text, camx + act2title.x, act2title.y, 7)
    rectfill(goose.x, act2title.y, camx + 64, act2title.y + 4, 0)
  end

  function fade_act2_title_bg()
    local fades = {}
    fades[3] = {3, 1, 0}
    fades[4] = {2, 1, 0}
    fades[10] = {4, 5, 0}

    local i = min(3, flr(39 - act2title.y))

    if i > 0 then
      for k, fade in pairs(fades) do
        pal(k, fade[i], 1)
      end
    end
  end

  function round_box_to_pixels(box)
    return {
      x1 = flr(box.x1),
      y1 = flr(box.y1),
      x2 = flr(box.x2),
      y2 = flr(box.y2)
    }
  end

  function actor_is_on_platform(actor, platform)
    local actorbox = round_box_to_pixels(get_actor_y_hitbox(actor))
    local platformbox = round_box_to_pixels(platform.box)

    return (actorbox.x2 >= platformbox.x1 and
      actorbox.x1 <= platformbox.x2 and
      actorbox.y2 == platformbox.y1 - 1)
  end

  function box_overlap(box1, box2)
    return (box1.x2 >= box2.x1 and
      box1.x1 <= box2.x2 and
      box1.y2 >= box2.y1 and
      box1.y1 <= box2.y2)
  end

  function create_actor(props)
    local defaults = {
      x = 0, y = 0,
      vx = 0, vy = 0,
      bottomoffset = 7,
      flipoffset = 0,
      spriteh = 8,
      draww = 8, drawh = 8,
      xhit = {w = 8, offset = 0},
      scale = 1,
      dir = -1,
      gravity = default_gravity,
      maxvx = max_velocity_x,
      maxvy = max_velocity_y,
      feetoffsets = {0, 0},
      friction = {air = .8, ground = .3},
      bounce = {},
      oldstate = {support = true},
      isenabled = true,
      anim = props.anims.default
    }

    -- overwrite default values
    for k, v in pairs(props) do
      defaults[k] = v
    end

    add(actors, defaults)

    return defaults
  end

  function get_actor_x_hitbox(actor)
    local box = {
      x1 = actor.x + actor.xhit.offset,
      x2 = actor.x + actor.xhit.offset + actor.xhit.w - 1,
      y1 = actor.y + actor.bottomoffset - (actor.drawh - 1),
      y2 = actor.y + 7
    }
    
    if actor.dir == 1 then
      box.x1 = actor.x + 8 - (actor.xhit.offset + actor.xhit.w - actor.flipoffset)
      box.x2 = box.x1 + actor.xhit.w - 1
    end

    return box
  end

  function get_actor_y_hitbox(actor)
    local box = {
      x1 = actor.x + actor.feetoffsets[1],
      x2 = actor.x + actor.feetoffsets[2],
      y2 = actor.y + actor.bottomoffset
    }

    box.y1 = box.y2

    return box
  end

  function create_anim(indexes, delay, loop)
    if loop == nil then loop = false end

    return {
      indexes = indexes,
      i = 1,
      timer = create_timer(delay),
      loop = loop,
      update =
        function(self)
          if self.timer:update() then
            self.timer:reset()

            if self.i < #self.indexes then
              self.i += 1
            elseif self.loop then
              self:restart()
            end
          end
        end,
      get_index = 
        function(self)
          return self.indexes[self.i]
        end,
      restart =
        function(self)
          self.i = 1
          self.timer:reset()
        end,
      is_done =
        function(self)
          return (self.i == #self.indexes and self.timer.value == 1)
        end
    }
  end

  function create_pond()
    return {
      anim = create_anim({18, 19}, fps, true),
      tiles = {},
      offset = {
        x = 0, 
        dir = -1,
        timer = create_timer(fps / 2)
      }
    }
  end

  function draw_actor(actor)
    local i = actor.anim:get_index()

    local xoffset = 0
    local flipx = false
    if actor.dir == 1 then
      flipx = true

      xoffset = actor.flipoffset
    end

    if actor.palette then
      for entry in all(actor.palette) do
        pal(entry[1], entry[2])
      end
    end

    if actor.scale == 1 and actor.spriteh == 8 and false then
      spr(i, actor.x + xoffset, actor.y, 1, 1, flipx)
    else
      -- convert the sprite index to an xy position on the sprite sheet
      local sx = (i % 16) * 8
      local sy = flr(i / 16) * 8

      sspr(sx, sy,
           8, actor.spriteh,
           actor.x + xoffset, actor.y,
           8 * actor.scale, actor.spriteh * actor.scale,
           flipx)
    end

    pal()
  end

  function draw_foods()
    for food in all(foods) do
      draw_actor(food)
    end
  end

  function draw_items()
    for item in all(items) do
      spr(item.sprite, item.x, item.y)
    end
  end

  function draw_actors()
    for a in all(actors) do
      if a.isenabled and not a.isfood then
        draw_actor(a)
      end
    end
  end

  function draw_ponds()
    for pond in all(ponds) do
      local i = pond.anim:get_index()
      for xy in all(pond.tiles) do
        spr(i, (xy[1] * 8) + pond.offset.x, xy[2] * 8)
      end
    end
  end

  function find_ponds()
    local pond = nil

    for x = 0, 128 do
      local columnhaswater = false
      for y = 0, 8 do
        if fget(mget(x, y), 4) then
          if not pond then
            pond = create_pond()
            pond.x1 = x * 8
          end

          add(pond.tiles, {x, y})
          columnhaswater = true
        end
      end

      -- if we've gone past the last column of this pond, finalize this pond
      if pond and not columnhaswater then
        -- find the highest y of the pond
        local y1 = pond.tiles[1][2]

        -- add an extra column to the right of the pond, to accommodate for the
        -- offset in the animation
        for tiley = y1, 7 do
          add(pond.tiles, {x, tiley})
        end

        -- save this pond and make way for the next one
        pond.x2 = (x * 8) - 1
        add(ponds, pond)
        pond = nil
      end
    end
  end

  function solid_down(x, y, fallthrough)
    local index = mget(x / 8, y / 8)

    if fget(index, 2) and flr(y) % 8 == 0 then
      -- allow falling through land if it's not ground (flag 1 + 2)
      if fallthrough and not fget(index, 1) then
        return false
      end

      return true
    else
      return false
    end
  end

  function solid_x(x, y)
    -- always collide with the far left boundary of the map
    if x == -1 then
      return true
    end

    local index = mget(x / 8, y / 8)
    return fget(index, 1)
  end

  function liquid(x, y)
    local index = mget(x / 8, y / 8)
    return fget(index, 4)
  end

  function move_actor_to_checkpoint(actor)
    if actor.checkpoint then
      actor.x = actor.checkpoint.x
      actor.y = actor.checkpoint.y
      actor.dir = actor.checkpoint.dir
      actor.vx = 0
      actor.vy = 0
    end
  end

  -- if the actor is intersecting with a checkpoint, save that as the actor's
  -- current checkpoint
  function save_checkpoint(actor)
    local actorbox = get_actor_y_hitbox(actor)

    for checkpoint in all(checkpoints) do
      local checkpointbox = {
        x1 = checkpoint.x,
        y1 = 0,
        x2 = checkpoint.x + 7,
        y2 = 64
      }

      if box_overlap(actorbox, checkpointbox) then
        actor.checkpoint = {
          x = checkpoint.x,
          y = checkpoint.y,
          dir = actor.dir
        }
        break
      end
    end
  end

  function find_things_on_map()
    for x = 0, 128 do
      for y = 0, 8 do
        local s = mget(x, y)
        local actor
        local xscaled = x * 8
        local yscaled = y * 8

        -- if there is a checkpoint tile here
        if s == 32 then
          local checkpoint = {
            x = xscaled,
            y = yscaled
          }
          add(checkpoints, checkpoint)
        end

        if s == 1 then
          actor = kitty
        elseif s == 8 then
          actor = boatduck
        elseif s == 9 then
          actor = fatduck
        elseif s == 11 then
          actor = goose
        end

        if actor then
          actor.x = xscaled
          actor.y = yscaled
        end
      end
    end
  end

  function collide_x(actor, endx)
    local startx = actor.x
    local dir

    if endx > startx then
      dir = 1 
    elseif endx < startx then
      dir = -1
    else
      return false
    end

    local hit = false
    for x = startx, endx, dir do
      local checkx = flr(x)

      local testactor = {
        x = checkx,
        y = actor.y,
        dir = actor.dir,
        xhit = actor.xhit,
        bottomoffset = actor.bottomoffset,
        flipoffset = actor.flipoffset,
        drawh = actor.drawh
      }

      local box = get_actor_x_hitbox(testactor)

      if dir == -1 then
        if solid_x(box.x1 - 1, box.y1) or solid_x(box.x1 - 1, box.y2) then
          hit = true
        end
      elseif dir == 1 then
        if solid_x(box.x2 + 1, box.y1) or solid_x(box.x2 + 1, box.y2) then
          hit = true
        end
      end

      if hit then
        if actor.isfood and actor.support ~= 'water' then
          -- give the food a bounce in the opposite direction
          actor.bounce.vx = -dir * abs(actor.vx) * .5
        end

        actor.x = flr(x)

        return true
      end
    end
  end

  function collide_y(actor, endy)
    local starty = actor.y

    if endy < starty then
      return
    end

    local leftoffset = actor.feetoffsets[1]
    local rightoffset = actor.feetoffsets[2]
    local x1 = actor.x + leftoffset
    local x2 = actor.x + rightoffset

    local hit = false
    for y = starty, endy, 1 do
      if actor.isfood then
        local checky = flr(y) + 7
        if liquid(x1, checky) or liquid(x2, checky) then
          hit = true
          actor.y = checky - 7
          actor.support = 'water'
        end
      end

      local testactor = {
        x = actor.x,
        y = y,
        feetoffsets = actor.feetoffsets,
        bottomoffset = actor.bottomoffset
      }

      local y2 = testactor.y + testactor.bottomoffset

      if solid_down(x1, y2 + 1, actor.isfallingthroughplatform) or
         solid_down(x2, y2 + 1, actor.isfallingthroughplatform) then
        hit = true
      end

      if not hit and not actor.isfallingthroughplatform then
        for sp in all(springplatforms) do
          if sp.actor ~= actor then
            for _, platform in pairs(sp.platforms) do
              if actor_is_on_platform(testactor, platform) then
                hit = true
                actor.y = platform.box.y1 - 8
                actor.support = sp.actor
                add(platform.occupants, actor)

                if actor == player then
                  -- give the platform a hit
                  platform.hit = {vy = actor.vy}
                elseif actor.isfood then
                  -- give the food a bounce upward
                  actor.bounce.vy = -actor.vy * .5
                end

                break
              end
            end
          end
        end
      end

      if hit then
        if not actor.support then
          -- set the actor's support to "generic platform"
          actor.support = true

          actor.y = flr(y)

          -- if the actor just landed
          if actor == kitty and not actor.oldstate.support then
            sfx(11)
          end
        end
        return true
      end
    end
  end

  function update_items()
    local playerbox = get_actor_y_hitbox(player)
    playerbox = round_box_to_pixels(playerbox)

    local newitems = {}
    for item in all(items) do
      if (box_overlap(playerbox, item.box)) then
        -- pick up the item, i.e. do not add it to the new items table
        if item.sprite == 36 then
          sfx(1)
          player.hasfood = true
        end
      else
        add(newitems, item)
      end
    end

    items = newitems
  end

  -- create a spring platform group, which is attached to/part of an existing
  -- actor
  function create_spring_platform(actor, platforms)
    return {
      actor = actor,
      originalposition = {x = actor.x, y = actor.y},
      offset = {x = 0, y = 0},
      tightness = .15,
      damping = .3,
      platforms = platforms,

      receive_hits =
        function(self)
          for _, platform in pairs(self.platforms) do
            if platform.hit then
              -- add the hit's y-velocity to the actor
              self.actor.vy += platform.hit.vy

              -- consume the hit
              platform.hit = nil
            end
          end
        end,

      count_occupants =
        function(self)
          for p in all(self.platforms) do
            return #p.occupants
          end
          return 0
        end,

      apply_spring_force =
        function(self)
          local velocitydelta
          velocitydelta = self.tightness *
            (self.originalposition.y - self.actor.y)
          velocitydelta = velocitydelta - (self.actor.vy * self.damping)

          self.actor.vy += velocitydelta

          -- apply a gate to the velocity
          local gate = .025
          if self:count_occupants() > 0 then
            gate = .01
          end
          if abs(self.actor.vy) < gate and
             abs(self.originalposition.y - self.actor.y) < gate
          then
            self.actor.vy = 0
            self.actor.y = self.originalposition.y
          end
        end,

      check_for_y_collision =
        function(self, overridevy)
          -- if we are not moving up
          if self.actor.vy >= 0 and not overridevy then
            -- do not check for collision with actors
            return
          end

          for _, platform in pairs(self.platforms) do
            local newy = platform.box.y1 + (overridevy or self.actor.vy)

            local testplatformbox = shallow_copy(platform.box)
            for y = platform.box.y1, newy, -1 do
              for actor in all(actors) do
                if actor ~= self.actor and not actor.isfallingthroughplatform then
                  testplatformbox.y1 = y
                  testplatformbox.x1 = flr(testplatformbox.x1)
                  testplatformbox.x2 = flr(testplatformbox.x2)

                  local actorbox = get_actor_y_hitbox(actor)
                  actorbox.x1 = flr(actorbox.x1)
                  actorbox.x2 = flr(actorbox.x2)
                  actorbox.y1 = actorbox.y2

                  -- if we are overlapping with the bottom of the actor
                  if box_overlap(testplatformbox, actorbox) then
                    -- put the actor on the platform and move the actor up to
                    -- where we are about to be
                    actor.support = self.actor
                    actor.y = newy - 8
                  end
                end
              end
            end
          end
        end,

      move_occupants =
        function(self)
          for _, platform in pairs(self.platforms) do
            for occupant in all(platform.occupants) do
              if not occupant.isfallingthroughplatform then
                -- move our occupant on the y-axis with us
                occupant.y = platform.box.y1 - 8

                -- if our parent actor moved on the x-axis
                if self.actor.x ~= self.actor.oldstate.x then
                  local pixeldelta = 
                    flr(self.actor.x) -
                    flr(self.actor.oldstate.x)

                  -- move the occupant by the same amount
                  occupant.x += pixeldelta
                end
              end
            end
          end
        end,

      on_direction_change =
        function(self)
          for _, platform in pairs(self.platforms) do
            for occupant in all(platform.occupants) do
              -- if our parent actor changed directions
              if self.actor.dir ~= self.actor.oldstate.dir then
                -- flip the occupant
                occupant.dir = -occupant.dir

                local oldoffset = flr(occupant.x) - flr(self.actor.x)
                occupant.x = self.actor.x - oldoffset - occupant.flipoffset
              end
            end
          end
        end,

      update_platform_boxes =
        function(self)
          for _, platform in pairs(self.platforms) do
            local scale = self.actor.scale

            local x = self.actor.x
            if self.actor.dir == -1 then
              x += platform.offset.x * scale
            end

            local y = self.actor.y + (scale * 8) - (platform.offset.y * scale)
            local w = platform.w * scale

            platform.box = {
              x1 = x,
              y1 = y,
              x2 = x + (w - 1),
              y2 = y
            }
          end
        end,

      update =
        function(self)
          -- update the box caches, since self.actor's position may have
          -- changed in update_actors() which is called before this
          self:update_platform_boxes()
          self:receive_hits()

          self:apply_spring_force()

          -- update the box caches again, since self.actor's position may have
          -- changed in apply_spring_force()
          self:update_platform_boxes()

          self:check_for_y_collision()
        end
    }
  end

  function apply_x_velocity(actor)
    local endx = actor.x + actor.vx
    local hit = collide_x(actor, endx)
    if hit then
      actor.vx = 0

      if actor.bounce.vx then
        actor.vx = actor.bounce.vx
        actor.bounce.vx = nil
      end
    else
      actor.x = endx
    end
  end

  function apply_y_velocity(actor)
    -- if the actor has a spring platform
    if actor.spring then
      -- leave all y physics to the spring platform
      return
    end

    local endy = actor.y + actor.vy
    local hit = collide_y(actor, endy)
    if hit then
      actor.vy = 0

      if actor.bounce.vy then
        actor.vy = actor.bounce.vy
        actor.bounce.vy = nil
      end
    else
      actor.y = endy
    end
  end

  function apply_physics(actor)
    if actor.didphysics then
      return
    end
    actor.didphysics = true

    -- add gravity
    actor.vy += actor.gravity

    -- if the actor is not walking
    if not actor.iswalking then
      local f

      -- if the actor is on a platform
      if actor.support then
        f = actor.friction.ground
      else
        f = actor.friction.air 
      end

      -- add friction
      actor.vx *= f

      if abs(actor.vx) < .01 then
        actor.vx = 0
      end
    end

    -- enforce maximum x velocity
    if actor.vx > actor.maxvx then
      actor.vx = actor.maxvx
    elseif actor.vx < -actor.maxvx then
      actor.vx = -actor.maxvx
    end

    -- enforce terminal velocity for falling
    if actor.vy > actor.maxvy then
      actor.vy = actor.maxvy
    end

    -- apply x velocity and hand x-axis collision
    apply_x_velocity(actor)

    -- apply y velocity, and handle y-axis collision
    actor.support = nil
    apply_y_velocity(actor)

    -- enforce coordinate boundaries, if defined
    if actor.minx then
      if actor.x < actor.minx then
        actor.x = actor.minx
      end
    end
    if actor.maxx then
      if actor.x > actor.maxx then
        actor.x = actor.maxx
      end
    end
  end

  function create_food(owner)
    local food = create_actor({
      anims = {default = create_anim({16}, 0)},
      friction = {air = 1, ground = .5},
      x = owner.x + 6,
      y = owner.y - 3,
      vx = owner.dir + owner.vx,
      vy = -2 + owner.vy,
      dir = owner.dir,
      flipoffset = -7,
      draww = 1,
      drawh = 1,
      ttl = create_timer(5 * 30),
      isfood = true
    })
    food.xhit.w = 1

    if owner.dir == 1 then
      food.x -= owner.flipoffset + 1
    end

    return food
  end

  function btn_pushed(b)
    if player.isenabled then
      if b == 4 then
        if player == kitty and player.support then
          if player.iscrouching then
            -- jump down
            player.vy = 1
            player.isfallingthroughplatform = true
          else
            -- jump
            sfx(0)
            player.vy = -3.2
          end
        elseif player == boatduck then
          boatduck.state = 'chomp'
        end
      elseif b == 5 then
        if player.hasfood then
          sfx(2)
          food = create_food(player)
          add(foods, food)
        end
      end
    end
  end

  function process_player_input()
    player.iswalking = false

    local delta = .16
    -- if the player is in the air
    if not player.support then
      -- decrease the amount of control
      delta = delta * .75
    end
    if btn(0) then
      player.dir = -1

      if player.vx > 0 then
        delta *= 1.5
      end

      player.vx -= delta
      player.iswalking = true
    elseif btn(1) then
      player.dir = 1

      if player.vx < 0 then
        delta *= 1.5
      end

      player.vx += delta
      player.iswalking = true
    end

    if not player.iswalking and btn(3) then
      player.iscrouching = true
    else
      player.iscrouching = false
    end

    -- if the player is moving up and not holding the jump button
    if player.vy < 0 and not btn(4) then
      -- cap the maximum upward velocity
      if player.vy < -1 then
          player.vy = -1
      end
    end
  end

  function update_act2_title()
    repeat yield() until goose.x == camx + 63
    music(0)

    local frames = 0
    while frames < 6 * fps do
      frames += 1

      if act2title.y > 30 then
        act2title.y -= .2
      end

      yield()
    end

    -- start game2
    game2()
    game2_init()
  end

  function update_actors()
    for actor in all(actors) do
      if actor.isenabled then
        apply_physics(actor)
        update_anim_state(actor)
      end
    end

    if fatduck.spring.platforms.head then
      update_fatduck_platform_positions()
    end
  end

  function remove_expired_foods()
    local newfoods = {}
    for food in all(foods) do
      if food.ttl:update() or food.iseaten then
        if not food.iseaten then
          food.isexpired = true
        end
        del(actors, food)
      else
        add(newfoods, food)
      end
    end
    foods = newfoods
  end

  function distance_from_duck_mouth(duck, food)
    local d1 = abs(food.x - duck.x)
    local d2 = abs(food.x - (duck.x + 7))

    if d2 < d1 then
      return d2, 1
    else
      return d1, -1
    end
  end

  function find_nearest_food(duck)
    -- find the nearest food
    local nearest = {food = nil, dist = 99}
    for food in all(foods) do
      -- if the food is on water
      if food.support == 'water' then
        -- if the food is in the same pond as the duck
        if food.x >= duck.pond.x1 and food.x <= duck.pond.x2 then
          local dist = distance_from_duck_mouth(duck, food)
          if dist  < nearest.dist then
            nearest.dist = dist
            nearest.food = food
          end
        end
      end
    end

    return nearest.food
  end

  function on_camera_moved()
    -- if we are on a special screen where the player is chasing a goose
    if camx >= 448 then
      -- if the player is getting too far behind the goose
      if player.x < goose.x - 32 then
        local teleportx = camx + 16
        -- if the goose has not already been teleported to this location
        if teleportx > goose.minteleportx then
          goose.x = teleportx
          goose.minteleportx = teleportx
        end
      end

      -- if we are on the special act 2 title screen
      if camx == 576 then
        -- put the goose in the starting position for revealing the title text
        goose.x = camx + 1

        gamestate = 'act2 title'
        player.isenabled = false
      end

      -- make sure the goose looks as though it never stopped moving
      goose.vx = max_velocity_x
    elseif player == boatduck then
      kitty.x = 0
      if gamestate ~= 'credits' then
        gamestate = 'credits'
        music(4)
      end
    end
  end

  function update_camera()
    if camy < 0 then
      local speed = -camy * .08
      camy += speed
      if camy >= -0.5 then
        camy = 0
      end
    end

    local edgex = player.x + player.flipoffset
    if player.dir == 1 then
      edgex += (player.draww - 1)
    end

    if edgex < camx or edgex > camx + screen_w then
      -- move the camera to the next/previous "screen"
      camx = edgex - (edgex % screen_w)

      on_camera_moved()
    end

    camx = max(0, camx)
  end

  -- return true if the actor's position relative to the camera meets either of
  -- the following conditions:
  --   * the actor is on the same screen as the camera
  --   * the actor is one screen away
  function actor_is_within_one_screen_away(actor)
    return (actor.x + actor.draww > camx - 64 and actor.x < camx + 128)
  end

  function update_npcs()
    if actor_is_within_one_screen_away(boatduck) and player ~= boatduck then
      update_boatduck()
    end

    if actor_is_within_one_screen_away(fatduck) then
      update_fatduck()
    end

    if actor_is_within_one_screen_away(goose) then
      update_goose()
    end
  end

  function update_boatduck()
    boatduck.iswalking = false
    boatduck.state = 'wait'

    if boatduck.nearestfood and boatduck.nearestfood.isexpired then
      boatduck.nearestfood = nil
    end

    if boatduck.nearestfood then
      local food = boatduck.nearestfood
      -- apply food physics early so we aren't one frame behind its actual
      -- position
      apply_physics(food)

      local dist, targetdir = distance_from_duck_mouth(boatduck, food)

      local targetx
      for i = 1, 2 do
        targetx = (targetdir == -1 and food.x or food.x - 7)

        -- if the duck cannot face the food in the targetdir because it is too
        -- close to the edge of the pond, reverse the targetdir
        if targetx < boatduck.minx then
          targetdir = -1
        elseif targetx > boatduck.maxx then
          targetdir = 1
        else
          break
        end
      end

      -- turn to face the target
      boatduck.dir = targetdir
      boatduck.spring:on_direction_change()

      -- set velocity to ease toward the food
      boatduck.vx = (targetx - boatduck.x) *.08

      -- if the duck is within chomping range
      if dist < 1 then
        -- if the duck's chomp animation is at the eating frame
        if boatduck.anim == boatduck.anims.chomp and boatduck.anim.i == 2 then
          -- consume the food
          boatduck.nearestfood.iseaten = true
          boatduck.nearestfood = nil
          boatduck.state = 'wait'
        else
          boatduck.state = 'chomp'
        end
      end
    else
      -- if the chomp animation is done playing
      if boatduck.anim ~= boatduck.anims.chomp or boatduck.anim:is_done() then
        -- find a new food to go after
        boatduck.nearestfood = find_nearest_food(boatduck)
      end
    end
  end

  function update_goose()
    goose.iswalking = false

    if goose.state == 'wait' then
      goose.gravity = 0

      -- if the player is close enough
      if player.x >= 396 then
        goose.state = 'rise'
        sfx(32)
      end
    elseif goose.state == 'rise' then
      if goose.y > 37 then
        goose.y -= 1
      else
        goose.gravity = default_gravity
        goose.state = 'turn'
      end
    elseif goose.state == 'turn' then
      goose.dir = 1
      goose.state = 'run'
    elseif goose.state == 'run' then
      goose.iswalking = true

      local delta = .16
      goose.vx += delta
    end
  end

  function pre_update_spring_platforms()
    for sp in all(springplatforms) do
      for _, platform in pairs(sp.platforms) do
        platform.occupants = {}
      end
    end
  end

  function update_spring_platforms()
    for sp in all(springplatforms) do
      sp:update()
    end

    update_spring_platform_actor_positions()

    -- update the spring platforms' box caches, since their actor's positions may
    -- have changed in update_spring_platform_actor_positions()
    for sp in all(springplatforms) do
      sp:update_platform_boxes()
    end

    -- move the occupants of each spring platform
    for sp in all(springplatforms) do
      sp:move_occupants()
    end
  end

  function table_contains(t, value)
    for v in all(t) do
      if v == value then
        return true
      end
    end
  end

  function update_spring_platform_actor_positions()
    -- create a table of unique actors
    local uniqueactors = {}
    for platform in all(springplatforms) do
      if not table_contains(uniqueactors, platform.actor) then
        add(uniqueactors, platform.actor)
      end
    end

    for actor in all(uniqueactors) do
      actor.y += actor.vy
    end
  end

  function slow_down_sfx(n)
    local sfxaddr = 0x3200 + (68 * n)

    for i = 0, 31 do
      local noteoffset = (i * 2)
      local byte1 = peek(sfxaddr + noteoffset)
      local pitch = band(byte1, 63)

      pitch -= 2

      -- zero the pitch in our copy of the byte
      byte1 = band(byte1, 64)

      -- put the new pitch back in the byte
      byte1 = bor(byte1, pitch)

      -- write the modified byte back to the sfx
      poke(sfxaddr + noteoffset, byte1)
    end

    -- slow down the sfx speed
    local lenaddr = sfxaddr + 65
    local len = peek(lenaddr)
    poke(lenaddr, len + 2)
  end

  function set_duck_scale(duck, scale)
    if scale > 11 then
      return
    end

    sfx(12)
    slow_down_sfx(12)

    if not duck.prescale then
      duck.prescale = {
        position = {
          x = duck.x,
          y = duck.spring.originalposition.y
        }
      }
      duck.spring.prescale = {
        tightness = duck.spring.tightness,
        damping = duck.spring.damping
      }
    end

    duck.scale = scale

    if duck.scale > 1 then
      if not duck.spring.platforms.head then
        -- enable the head and bill spring platforms
        duck.spring.platforms.head = duck.spring.disabled_platforms.head
        duck.spring.platforms.bill = duck.spring.disabled_platforms.bill

        duck.spring.platforms.head.occupants = {}
        duck.spring.platforms.bill.occupants = {}
      end
    end

    duck.x = duck.prescale.position.x - (scale / 4)
    duck.y = duck.prescale.position.y - ((scale - 1) * 8)
    duck.spring.originalposition.y = duck.y

    duck.spring.damping = duck.spring.prescale.damping + (scale / 25)

    -- update the spring platform box caches, since the duck just moved (above)
    duck.spring:update_platform_boxes()

    for _, platform in pairs(duck.spring.platforms) do
      -- keep the occupants on top of the platform
      for occupant in all(platform.occupants) do
        occupant.y = platform.box.y1 - 8

        if occupant.x + occupant.feetoffsets[1] <= platform.box.x1 then
          occupant.x = platform.box.x1 - occupant.feetoffsets[1]
        end
      end
    end
  end

  function get_food_at_mouth(duck)
      for food in all(foods) do
        if food.support == 'water' then
          local foodx = flr(food.x)
          if foodx >= duck.x - 1 and foodx <= duck.x + (duck.scale - 1) then
            return food
          end
        end
      end
  end

  function update_fatduck_platform_positions()
    local headoffset = fatduck.spring.platforms.head.offset
    local billoffset = fatduck.spring.platforms.bill.offset
    local oldbilloffsety = billoffset.y

    -- if the duck is lowering its head, move the platforms attached to the
    -- head 
    if fatduck.anim == fatduck.anims.chomp then
      if fatduck.anim.i == 1 or fatduck.anim.i == 3 then
        headoffset.y = 3
        billoffset.y = 2
      elseif fatduck.anim.i == 2 then
        headoffset.y = 2
        billoffset.y = 1
      end
    else
      headoffset.y = 4
      billoffset.y = 3
    end

    if billoffset.y > oldbilloffsety then
      fatduck.spring:check_for_y_collision(
        (oldbilloffsety - billoffset.y) * fatduck.scale)
      update_anim_state(kitty, true)
    end
  end

  function update_fatduck()
    if fatduck.targetfood then
      if fatduck.targetfood.iseaten or fatduck.targetfood.isexpired then
        fatduck.state = 'wait'
        fatduck.targetfood = nil
      else
        fatduck.state = 'chomp'
      end
    end

    if fatduck.targetfood and fatduck.state == 'chomp' then
      -- if the duck's chomp animation is at the eating frame
      if fatduck.anim == fatduck.anims.chomp and fatduck.anim.i == 2 then
        -- consume the food
        fatduck.targetfood.iseaten = true
        fatduck.targetfood = nil

        -- grow bigger
        set_duck_scale(fatduck, fatduck.scale + 1)
      end
    elseif fatduck.state == 'wait' then
      fatduck.targetfood = get_food_at_mouth(fatduck)
    end
  end

  function update_anim_state(actor, noupdate)
    if actor.iswalking then
      if actor.anim ~= actor.anims.walk and
        actor.anim ~= actor.anims.turn and
        actor.anim ~= actor.anims.landwalk then
        if actor.anims.walk then
          actor.anim = actor.anims.walk
          actor.anim:restart()
        end
      end
    end

    if actor.anims.crouch then
      if actor.iscrouching then
        actor.anim = actor.anims.crouch
      elseif actor.anim == actor.anims.crouch then
        actor.anim = actor.anims.default
      end
    end

    if actor.anims.walk then
      -- if the actor is walking slowly
      if abs(actor.vx) < actor.maxvx * .25 then
        -- play the walk animation more slowly
        actor.anims.walk.delay = 8
      else
        actor.anims.walk.delay = 4
      end
    end

    -- if the actor is skidding from changing direction suddenly
    local suddenturn = false
    local sudden_turn_velocity = actor.maxvx * .1
    if actor.dir == 1 and actor.vx < 0 then
      suddenturn = true
    elseif actor.dir == -1 and actor.vx > 0 then
      suddenturn = true
    end
    if suddenturn then
      if actor.anims.turn then
        actor.anim = actor.anims.turn
        actor.anim:restart()
      end
    end

    if not actor.support then
      if actor.anims.jump then
        actor.anim = actor.anims.jump
        actor.anim:restart()
      end
    end

    -- if the actor just landed
    if not actor.oldstate.support and actor.support then
      if actor.anims.land then
        actor.anim = actor.anims.land
        actor.anim:restart()
      end

      if actor.iswalking then
        if actor.anims.landwalk then
          actor.anim = actor.anims.landwalk
          actor.anim:restart()
        end
      end
    end

    -- duck: if state is 'chomp' do chomp animation
    if actor.state == 'chomp' and actor.anim ~= actor.anims.chomp then
      actor.anim = actor.anims.chomp
      actor.anim:restart()
    end
    -- duck: if the chomp animation is done playing
    if actor.anim == actor.anims.chomp and actor.anim:is_done() then
      actor.state = 'wait'
    end

    -- if the current animation is done playing
    if actor.anim.timer.length ~= 0 and actor.anim:is_done() then
      actor.anim = actor.anims.default
    end

    if not noupdate then
      -- update the animation
      actor.anim:update()
    end
  end

  function post_update_actors()
    for actor in all(actors) do
      actor.oldstate = {
        x = actor.x,
        y = actor.y,
        dir = actor.dir,
        support = actor.support
      }

      actor.isfallingthroughplatform = false
      actor.didphysics = false
    end

    -- if the player has fallen off the bottom of the screen
    if kitty.y > 64 then
      sfx(3)
      move_actor_to_checkpoint(kitty)
    end
  end

  function update_ponds()
    for pond in all(ponds) do
      pond.anim:update()

      local offset = pond.offset
      if offset.timer:update() then
        offset.timer:reset()
        offset.x += offset.dir

        for food in all(foods) do
          if food.support == 'water' then
            -- move the piece of food with the water
            food.vx += pond.offset.dir
          end
        end

        if offset.x == -8 then
          offset.dir = 1
        elseif offset.x == 0 then
          offset.dir = -1
        end
      end
    end
  end
end

function game2()
  -- global constants
  textpanew = 14 -- width of text pane (in characters)
  numdecoys = 2
  painting_x = 2
  painting_y = 27
  painting_w = 61
  painting_h = 99
  day_names = {
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday'
  }


  -- optional properties:
  -- * h
  -- * iswindow
  function create_menu(name, items, x, y, w)
    return {
      name = name,
      items = items,
      x = x,
      y = y,
      w = w,
      sel = 1,
      rowh = 7,
      textoffsetx = 0,
      iswindow = true,
      autosize = function(self)
        -- automatically set the width to accomodate the widest item
        local longest = 0
        for item in all(self.items) do
          if #item > longest then
            longest = #item
          end
        end
        self.w = (longest * 4) + 19

        if self.icons then
          self.w += 10
          self.rowh = 9
          self.textoffsetx = 5
        end

        -- automatically set the height to accomodate the number of items
        self.h = (#self.items * self.rowh) + 8
      end,
      draw = function(self, top)
        if self.iswindow then
          draw_window(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1)
        end

        -- draw the items
        local x = self.x + (self.w / 2) + self.textoffsetx -- text x
        local y = self.y + 5 -- text y
        local hw = self.w - (self.textoffsetx * 2) - 10 -- highlight width
        for i, txt in pairs(self.items) do
          if self.icons then
            spr(self.icons[i], self.x + 5, y - 1)
          end

          if top and i == self.sel and (self.flash == nil or self.flash % 4 <= 1) then
            -- highlight this item
            rectfill(
              x - (hw / 2), y - 1,
              x + (hw / 2) - 1, y + 5,
              7)
            color(0)
          else
            color(7)
          end
          cprint(txt, x, y)
          y += self.rowh
        end

        if self.art then
          camera(-self.x - 2, -self.y)
          local shapes = parse_painting(self.art[1], self.art[2])
          render_shapes(shapes)
          camera()
        end
      end
    }
  end

  function draw_menus()
    local top = #menustack
    for i, menu in pairs(menustack) do
      menu:draw(i == top)
    end
  end

  function add_menu(m)
    m:autosize()
    add(menustack, m)
  end

  function execute_menu_item(menu, i)
    if menu.name == 'main' then
      if i == 1 then
        local m = create_menu(
          'investigate',
          {
            'question witness',
            here.action.desc,
            'call tipster'
          },
          13, 82)
        m.icons = {20, (here.action.sprite or 21), 22}
        add_menu(m)
      elseif i == 2 then
        local m = create_menu('notebook', {}, 32, 35, 65)
        m.h = 81
        m.art = notebook_art
        add(menustack, m)
      elseif i == 3 then
        local names = {}
        for loc in all(here.destinations) do
          add(names, loc.name)
        end

        local m = create_menu('walk', names, 19, 70, 90)
        m.h = 22
        add_menu(m)
      end
    elseif menu.name == 'investigate' then
      if i == 1 then
        local speaker, cluetext = get_clue()
        set_textpane_text(cluetext, speaker)
        wait(1)

        if here.islastlocation then
          local m = create_menu('duck', {'duck', 'duck', 'goose'}, 64, 99)
          m.iswindow = false
          m.w = 63
          menustack = {m}
        end

        exit_menu()
      elseif i == 2 then
        set_textpane_text(here.action.result)
        wait(2)
        exit_menu()
      elseif i == 3 then
        local text = tipster_clues[tipster_clue_index]

        if tipster_clue_index < #tipster_clues then
          tipster_clue_index += 1
        else
          tipster_clue_index = 1
        end

        set_textpane_text(text, 'tipster')

        wait(3)
        exit_menu()
      end
    elseif menu.name == 'walk' then
      local dest = here.destinations[i]
      local correct = false
      if dest == suspect.location then
        move_suspect()
        correct = true
      end

      set_location(dest)
      if correct then
        here.showgoose = true
      end

      wait(flr(rnd(3)) + 3)
      state = 'wait-walk'

      exit_menu()
      
      -- select "invesitigate" on main menu
      menustack[1].sel = 1
    elseif menu.name == 'duck' then
      state = 'distort'
    end
  end

  -- wrap text for printing in the text pane.
  function wrap(s, wrapw)
    if not wrapw then
      wrapw = textpanew
    end

    if #s <= wrapw then
      return s, 1
    end

    local new = ''

    local a = 1 -- current start character index
    local b = wrapw + 1 -- current end character index
    local numlines = 1
    while b > a do
      if sub(s, b, b) == ' ' then
        -- add this line with a line-break instead of the space
        new = new .. sub(s, a, b - 1) .. '\n'
        a = b + 1
        b = a + wrapw
        numlines += 1
      else
        b -= 1
      end

      if b > #s then
        b = #s
        new = new .. sub(s, a)
        break
      end
    end

    return new, numlines
  end

  function btn_pushed(b)
    if state == 'menu' then
      local menu = menustack[#menustack]

      if not menu.flash then
        local prevsel = menu.sel

        if b == 2 then
          if menu.sel > 1 then
            menu.sel -= 1
          end
        elseif b == 3 then
          if menu.sel < #menu.items then
            menu.sel += 1
          end
        end

        if menu.items[menu.sel] == 'goose' then
          -- swap the "goose" with the previously selected item
          menu.items[menu.sel], menu.items[prevsel] =
            menu.items[prevsel], menu.items[menu.sel]
        end

        if b == 4 then
          menu.flash = fps / 2
        elseif b == 5 then
          exit_menu()
        end
      end
    end
  end

  function update_menus()
    local menu = menustack[#menustack]

    if menu.flash ~= nil then
      if menu.flash >= 0 then
        menu.flash -= 1
      else
        menu.flash = nil
        execute_menu_item(menu, menu.sel)
      end
      return
    end
  end

  function exit_menu()
    if #menustack > 1 then
      -- pop the top menu off the stack
      menustack[#menustack] = nil
    end
  end

  function game2_init()
    -- switch to 128x128 mode
    poke(0x5f2c, 0)

    -- possible states:
    --   * wipe
    --   * menu
    --   * wait-menu
    --   * wait-walk
    --   * goose
    state = 'wipe'
    wipey = -16

    textpane = {
      x = 68,
      y = 5,
      text = ''
    }

    menustack = {}

    -- create the main menu
    local main = create_menu(
      'main',
      {
        'investigate',
        'notebook',
        'walk'
      },
      64, 99, 63)
    main.iswindow = false
    add(menustack, main)

    clock = {
      day = 3,
      hour = 9
    }
    hourtimer = create_timer(fps / 4)

    -- create all locations
    local l
    locations = {}

    -- 1. duck pond
    add_location({
      name = 'duck pond',
      description = 'did you know: the main difference between a duck and a goose is the number of bones it contains.',
      witness = 'park visitor',
      tryagain = '',
      action = {
        desc = 'pat the duck',
        result = 'please call him by his full name: patrick'
      }
    })

    -- 2. helsinki, finland
    add_location({
      name = 'helsinki, finland',
      description = 'helsinki was founded in 1550 by king goosetav i.',
      witness = 'santa claus',
      tryagain = 'sorry, i did not see a goose',
      action = {
        desc = 'make a snowman',
        result = 'you construct a snowman. you wonder if the snowman has seen any gooses. (no, it has not.)'
      },
      clue = 'that goose said something about visiting a country with a history of soviet conflict.'
    })

    -- 3. hospital
    add_location({
      name = 'hospital',
      description = 'did you know: even when dropped from a great height, a goose will not be hurt. this is because gooses have no bones.',
      witness = 'nurse',
      tryagain = 'of course not. gooses cannot be a doctor. only a nurse.',
      action = {
        desc = 'visit gramma',
        result = 'but your gramma is in another hospital!'
      },
      clue = 'the goose looked like it wanted to perform a surgery.'
    })

    -- 4. abandoned library
    add_location({
      name = 'abandoned library',
      description = 'did you know: the first book was printed in 1455 by johannes goosenberg, a german.',
      witness = 'ghost librarian',
      witness_ps = 'btw i am a librarian for ghosts, not the ghost of a librarian.',
      tryagain = 'you\'re looking for geese? try the non-fiction section.',
      action = {
        desc = 'browse shelves',
        result = 'you pick up a book and wipe away a layer of dust, revealing the title: "game programming for gooses".'
      },
      clue = 'the goose said it needed to look something up in an outdated almanac.'
    })

    -- address and length of each vector drawing
    arts = {
      {1536, 428},
      {1964, 1384},
      {3348, 1438},
      {4786, 710},
      {5496, 558},
      {6054, 40}
    }
    for i = 1, 4 do
      locations[i].art = arts[i]
    end
    notebook_art = arts[5]
    duck_art = arts[6]

    tipster_clue_index = 1
    tipster_clues = {
      'i heard that cindy has a crush on steve omg i know right',
      'lakisha and becky are totally fighting over michael, but like he doesn\'t even know. don\'t tell him i said that.',
      'raquel needs to lose like 20 lbs but like no one wants to tell her.',
      'i heard nina used to be a fish.',
      'mandy is really mad at fat mandy for taking her name.',
      'over summer break, mindy got totally addicted to pills.',
      'lisa said that steve said that donna said he saw rachel kiss mandy.',
      'omg i heard stephanie kissed a moose.',
    }
    
    init_suspect()
    move_suspect()

    -- choose the duck pond as the starting location
    local start = locations[1]
    start.nextlocation = suspect.location
    set_location(start)

    -- initialize distortion cutscene
    duckx = 0
    distort_shapes_cr = cocreate(distort_shapes)
    distort_phase = 0
  end

  function add_location(props)
    add(locations, props)
  end

  function rnd_choice(t)
    return t[flr(rnd(#t)) + 1]
  end

  function move_suspect()
    local newlocation

    -- if we have visited all locations
    if #suspect.unvisited == 0 then
      suspect.location.islastlocation = true
    else
      -- find a location we haven't visited
      newlocation = rnd_choice(suspect.unvisited)

      -- remove the new location from our list of unvisited locations
      del(suspect.unvisited, newlocation)
    end

    if suspect.location then
      -- tell our current location what our next location is
      suspect.location.nextlocation = newlocation
    end

    -- set the new location as our current location
    suspect.location = newlocation
  end

  function init_suspect()
    suspect = {
      unvisited = shallow_copy(locations)
    }

    -- remove the duck pond from the suspect's availabe locations
    del(suspect.unvisited, locations[1])
  end

  function wait(hours)
    waithours = hours
    state = 'wait-menu'

    -- add the first hour right away
    add_hour()
    waithours -= 1

    -- reset the timer to wait for the next hour
    hourtimer:reset()
  end

  function add_hour()
    sfx(10)

    if clock.hour < 23 then
      clock.hour += 1
    else
      clock.hour = 0

      if clock.day < #day_names then
        clock.day += 1
      else
        clock.day = 1
      end
    end
  end

  function get_clue()
    local clue = ''

    if here.islastlocation then
      for i = 1, 45 do
        clue = clue .. 'duck '
      end
    elseif here.nextlocation then
      clue = here.nextlocation.clue

      if here.witness_ps then
        clue = clue .. ' ' .. here.witness_ps
      end
    else
      clue = here.tryagain
    end

    return here.witness, clue
  end

  function draw_corner(x, y, dir)
    local sx = 72
    local sy = 8
    if dir == 2 then
      sx = 76
      x -= 3
    elseif dir == 3 then
      sx = 76
      sy = 12
      x -= 3
      y -= 3
    elseif dir == 4 then
      sy = 12
      y -= 3
    end

    sspr(sx, sy, 4, 4, x, y)
  end

  function draw_window(x1, y1, x2, y2)
    rectfill(x1 + 2, y1 + 2, x2 + 2, y2 + 2, 1) -- shadow
    rectfill(x1, y1, x2, y2, 7)
    rectfill(x1 + 2, y1 + 2, x2 - 2, y2 - 2, 0)
  end

  function draw_border(x1, y1, x2, y2)
    color(7)
    rect(x1, y1, x2, y2)
    rect(x1 + 1, y1 + 1, x2 - 1, y2 - 1)

    draw_corner(x1, y1, 1)
    draw_corner(x2, y1, 2)
    draw_corner(x2, y2, 3)
    draw_corner(x1, y2, 4)
  end

  function draw_borders()
    -- location area
    draw_border(0, 0, 64, 26)

    -- picture area
    draw_border(0, 25, 64, 127)

    -- text area
    draw_border(63, 0, 127, 100)

    -- main menu area
    draw_border(63, 99, 127, 127)
  end

  function draw_shape(shape)
    local points = shape.points
    color(shape.color)

    if #points == 1 then
      pset(points[1].x, points[1].y)
    elseif #points == 2 then
      line(points[1].x, points[1].y, points[2].x, points[2].y)
    elseif #points >= 3 then
      fill_polygon(shape)
    end
  end

  function ceil(n)
    return -flr(-n)
  end

  function find_bounds(points)
    local x1 = 32767
    local x2 = 0
    local y1 = 32767
    local y2 = 0
    for point in all(points) do
      x1 = min(x1, point.x)
      x2 = max(x2, point.x)
      y1 = min(y1, point.y)
      y2 = max(y2, point.y)
    end

    return x1, x2, y1, y2
  end

  function find_intersections(points, y)
    local xlist = {}
    local j = #points

    for i = 1, #points do
      local a = points[i]
      local b = points[j]

      if (a.y < y and b.y >= y) or (b.y < y and a.y >= y) then
        local x = a.x + (((y - a.y) / (b.y - a.y)) * (b.x - a.x))

        add(xlist, x)
      end

      j = i
    end

    return xlist
  end

  function fill_polygon(poly)
    color(poly.color)

    -- find the bounds of the polygon
    local x1, x2, y1, y2 = find_bounds(poly.points)

    for y = y2, y1, -1 do
      -- find intersecting nodes
      local xlist = find_intersections(poly.points, y)
      sort(xlist)

      -- draw the scanline
      for i = 1, #xlist - 1, 2 do
        local x1 = flr(xlist[i])
        local x2 = ceil(xlist[i + 1])

        line(x1, y, x2, y)
      end
    end
  end

  function sort(t)
    for i = 2, #t do
      local j = i
      while j > 1 and t[j - 1] > t[j] do
        t[j - 1], t[j] = t[j], t[j - 1]
        j -= 1
      end
    end
  end

  function render_shapes(shapes)
    for shape in all(shapes) do
      draw_shape(shape)
    end
  end

  function create_painting_reader(addr, len)
    return {
      offset = 0,
      addr = addr,
      len = len,

      get_next_byte = function(self)
        local byte = peek(self.addr + self.offset)
        self.offset += 1
        return byte
      end,

      is_at_end = function(self)
        return (self.offset >= self.len)
      end
    }
  end

  function parse_painting(addr, len)
    local shapes = {}

    -- read each shape
    local reader = create_painting_reader(addr, len)
    repeat
      local shape = {
        points = {}
      }

      -- read the point count
      local pointcount = reader:get_next_byte()

      -- read the color
      shape.color = reader:get_next_byte()

      -- read each point
      for i = 1, pointcount do
        local x = reader:get_next_byte()
        local y = reader:get_next_byte()

        -- adjust y back to its actual value since it is saved 1 higher than
        -- its actual value to allow for -1 without needing a sign bit
        y -= 1

        add(shape.points, {x = x, y = y})
      end

      add(shapes, shape)
    until reader:is_at_end()

    return shapes
  end

  function draw_here()
    -- 6912 avaiable bytes in "user data" area
    -- 3072 used by art cache
    local screenaddr = 0x6000 + (64 * painting_y)
    local cacheaddr = 0x4300
    local screenwidth = 0x40
    local rowsize = 32
    local numrows = painting_h

    if distort_phase < 2 then
      clip(painting_x, painting_y, painting_w, painting_h)
    end

    if artiscached and distort_phase == 0 then
      -- draw the cached pixels to the screen
      local src = cacheaddr
      local dest = screenaddr
      for y = 1, numrows do
        memcpy(dest, src, rowsize)
        dest += screenwidth
        src += rowsize
      end
    elseif here.shapes then
      camera(-painting_x + duckx, -painting_y)

      -- render all the shapes
      render_shapes(here.shapes)

      camera()

      -- cache the pixels
      local src = screenaddr
      local dest = cacheaddr
      local rowsize = 32
      for y = 1, numrows do
        memcpy(dest, src, rowsize)
        src += screenwidth
        dest += rowsize
      end
      artiscached = true
    end

    clip()
  end

  function set_textpane_text(txt, speaker)
    textpane.text = wrap(txt)

    if speaker then
      textpane.speaker, textpane.speakerh = wrap(speaker .. ':')
      textpane.chars = 0
    else
      textpane.speaker = nil
      textpane.chars = nil
    end
  end

  function get_destinations(prevloc)
    local dests = {}

    if prevloc then
      -- add our previous location
      add(dests, prevloc)
    end

    -- if the suspect's location is not the same as our previous location
    if suspect.location ~= prevloc then
      -- add the suspect's location to the list of destinations
      add(dests, suspect.location)
    end

    -- add decoy locations
    local decoys = get_decoy_locations(prevloc)
    for d in all(decoys) do
      add(dests, d)
    end

    return dests
  end

  function set_location(loc)
    local prevloc
    if here then
      prevloc = here
    end

    here = loc

    if not here.destinations then
      here.destinations = get_destinations(prevloc)
    end

    if here.art then
      here.shapes = parse_painting(here.art[1], here.art[2])
    end
    artiscached = false

    set_textpane_text(here.description)

    -- shuffle the destinations
    shuffle(here.destinations)
  end

  function get_decoy_locations(prevloc)
    local decoys = {}

    local dests = shallow_copy(locations)

    -- if there is a previous location
    if prevloc then
      -- remove the previous location from the list of available decoys
      del(dests, prevloc)
    end

    -- remove the suspect's location from the list of available decoys
    del(dests, suspect.location)

    -- remove the current location
    del(dests, here)

    for i = 1, numdecoys do
      local choice = rnd_choice(dests)
      del(dests, choice)
      add(decoys, choice)

      if #dests == 0 then
        break
      end
    end

    return decoys
  end

  function shuffle(t)
    -- do a fisher-yates shuffle
    for i = #t, 1, -1 do
      local j = flr(rnd(i)) + 1
      t[i], t[j] = t[j], t[i]
    end
  end

  function prepare_goose_departure()
    update_goose_departure_cr = cocreate(update_goose_departure)

    here.showgoose = false
    
    goose.x = 576
    goose.y = 0
    goose.vx = max_velocity_x
    goose.dir = 1
    goose.gravity = 0
    goose.state = 'run'

    music(1)
  end

  function update_goose_departure()
    repeat
      update_goose()
      goose.didphysics = false
      apply_physics(goose)
      update_anim_state(goose)
      yield()
    until goose.x > 660

    if not showedgoosetext then
      showedgoosetext = true
      state = 'goose-text'
      textpane.speaker = nil
      textpane.chars = nil
      textpane.text = '\n\n\n\n\n\n\n\n\nthere goes\ngoose!\n\nyou must be on\nthe right\ntrack.'

      sleep(fps * 4)

      set_textpane_text(here.description)
    end

    state = 'menu'
  end

  function _update()
    update_buttons()

    if state == 'menu' then
      update_menus()
      update_textpane()
    elseif sub(state, 1, 4) == 'wait' then
      -- if an hour has passed
      if hourtimer:update() then
        hourtimer:reset()

        if waithours > 0 then
          waithours -= 1
          add_hour()
        else
          if here.showgoose then
            prepare_goose_departure()
            state = 'goose'
          else
            state = 'menu'
          end
        end
      end
    elseif sub(state, 1, 5) == 'goose' then
      coresume(update_goose_departure_cr)
    elseif state == 'distort' then
      if costatus(distort_shapes_cr) == 'dead' then
        game1()
        game1_init()
        player = boatduck
        camy = 0
      else
        coresume(distort_shapes_cr)
      end
    end
  end

  function distort_shapes()
    music(2)
    distort_phase = 1

    -- define the target duck shapes
    local targets = parse_painting(duck_art[1], duck_art[2])

    local shapes = here.shapes

    -- set targets coordinates for all points in all shapes
    local t = 1
    for i, s in pairs(shapes) do
      local target = targets[t]
      local tpi = 1
      if #s.points < 3 then
        tpi = 3
      end

      s.tc = target.color
      s.sc = s.color

      for p in all(s.points) do
        p.sx = p.x
        p.sy = p.y

        local tp = target.points[tpi]
        p.dx = tp.x + 22
        p.dy = tp.y + 61

        if tpi < #target.points then
          tpi += 1
        end
      end

      if (#s.points >= 4 or i % flr(#shapes / #targets) == 0) and t < #targets then
        t += 1
      end
    end

    yield()

    local length = flr(fps * 8)
    if here == locations[2] then
      -- compensate for slow framerate in helsinki
      length = flr(fps * 6)
    end
    for f = 0, length do
      -- move each point toward its target
      for s in all(shapes) do
        for p in all(s.points) do
          p.x = ease_in_cubic(f, p.sx, (p.dx - p.sx), length)
          p.y = ease_in_cubic(f, p.sy, (p.dy - p.sy), length)
        end
      end

      yield()
    end

    sleep(fps)
    distort_phase = 2
    sleep(fps / 2)
    distort_phase = 3

    length = flr(fps * 4)
    for f = 0, length do
      duckx = ease_out_cubic(f, 0, (-72), length)

      if duckx < -25 then
        for s in all(shapes) do
          s.color = (flr(duckx) % 2 == 0 and s.tc or s.sc)
        end
      end

      yield()
    end

    repeat yield() until stat(16) == 33 and stat(20) >= 2
  end

  function sleep(frames)
    for i = 1, frames do
      yield()
    end
  end

  function draw_title_and_time()
    color(7)

    local title, numlines
    numlines = 1

    -- determine the title
    if state == 'wait-walk' then
      title = 'walking...'
    else
      title, numlines = wrap(here.name)
    end

    print(title, 5, 5)

    local dow = day_names[clock.day]
    local time = clock.hour .. ':00'

    if numlines > 1 then
      print(sub(dow, 1, 3) .. ' ' .. time, 5, 17)
    else
      print(dow .. '\n' .. time, 5, 11)
    end
  end

  function update_textpane()
    if textpane.chars and textpane.chars < #textpane.text then
      textpane.chars += 1
    end
  end

  function draw_textpane()
    local x, y = textpane.x, textpane.y

    clip(x, y, 56, 94)

    if textpane.speaker then
      print(textpane.speaker, x, y, 14)
      y += 6 * textpane.speakerh
    end

    local text = textpane.text

    if textpane.chars then
      text = sub(text, 1, textpane.chars)
    end

    print(text, x, y, 7)
    clip()
  end

  function draw_goose_departure()
    camera(521, -80)
    draw_actor(goose)
    camera()
  end

  function _draw()
    cls()
    pal()

    if state == 'goose' then
      draw_goose_departure()
    end

    if state ~= 'wait-walk' then
      draw_here()
    end

    if distort_phase < 2 then
      draw_borders()
      draw_title_and_time()
    end

    if state == 'menu' or state == 'wipe' or state == 'goose-text' then
      draw_textpane()
    end

    if state == 'menu' then
      draw_menus()
    end

    if state == 'wipe' then
      if wipey < 132 then
        wipey += 4
      else
        state = 'menu'
      end
      rectfill(0, wipey, 127, 128, 0)
    end
  end
end

game1()
game1_init()
sfx(31)

-- debug
--game2()
--game2_init()

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009700000000000000970000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000970000099770000097000009977000000000000
00000000002020200020202000202002002020200020200200000000020020200000000000000000000000009977000000770000997700000077000000000000
0000000000a2a0020022200200a2a02000a2a00200a2a020002020200020a2a00440000000000000000000000077000707700007007700070770000700000000
00000000002222200022222000222220002222200022222000a2a222000222209940000004400000000000000777777007777770077777700777777000000000
00000000000222200002222000022220000222200002222000222220000222200444444499444444044444447777777707777777777777770777777700000000
00000000000200200002002000020020002002020020000200020020002020020444444004444440994444400777777000777770077777700077777000000000
00000000333333331111111111111111008888000000660000000000000003300000000000000000000000000090090000900900009009000090090000000000
000000003333333311c111111111111108800880000677600555555000003b330000000000000000000000000090099000900990099009000990090000000000
00000000434434331c1c11111c1c11110880088000670006550000550003b3330000000000777700000000000990000009900000000009900000099000000000
00000000444444441111111111c111110000088000600006dd5005dd003333330000000000700700000000000000000000000000000000000000000000000000
00000000444444441111111111111111000088000006006000555500033333300020202000700700000000000000000000000000000000000000000000000000
000000004444444411111c11111111110008800000406600055665503333330000a2a22200777700000000000000000000000000000000000000000000000000
00000000444444441111c1c11111c1c1000000000400000005566550333330000022222000000000000000000000000000000000000000000000000000000000
a0000000444444441111111111111c11000880004000000005555550033300000020020200000000000000000000000000000000000000000000000000000000
008800004444444400000000dddddddd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a88880084444444400000000dddddddd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a88888884444444400000000dddddddd00a900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a88888884444444400000000dddddddd009a03000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a80088884444444400000000dddddddd30a930000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a00008804444444400303000dddddddd033a30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a00000004444444400330000dddddddd003330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a00000004444444400330000dddddddd0033000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
40300033c333c3360036c0f08064d0a411c4d115f26593a5d3c5c333f143f083a0e3804440c000000033c333c30040309033e00351236133d010c34372335173
f0b3c004b034c0646194e1b472e4e2f45315e3f460b0c34563e48305c31593c4b315a0b0331523f4f2e433d403a443d4639443e493b4430520c0e024214430c0
21b331a311d3b0400315f2f4c2d4a2e403d4d29413d4239403e453c423f49040833533f41305730543c4830583c48315b3d42090c04460332090f014d0232090
f044b063209021e3011340407063607380b3a0b33040b063c0c3d0b34040d043d033f093e0a34040f023117321630133f07040f090c041c0b111020152316251
2271a1813181f0a190a100c100910011d060c3d173c123e1d20272121202d122c14222627272d2725392c372c03022935263829372c3d2b3f293d2e3c2045204
32e342b342a3209012934293404082c3c2c392f362f350b0003300e250e2a013c03340b041337113b123e14320c07224321430c061249134d15420c04294a2b4
2000528352834060613680f500b50036205050d5713640600083803320530063205090f50036205040d500b540300010c300c3a300a390b00040b090a0d06131
7111c0a032509130517030b05332c322c34240b071a1f25152b171c140b0f2e091b071d0e23140b04130f040d000d01040b03141f0410171217150b0c3107330
834033b0839060b06062106230c200e2002340c250b000a080f08041300100e050b0938253b223d283d273b260b03191f0b101e1e012211241d150b000611061
00a110e1001290b0a311f2615371638163a103c113f19371535160b043604340c2308270e2b003806060c334b274c0741084d244c33480700063904361138203
8333c333c3360036a060c373d2636293719301c300b3b0d361b3328323736060c3c381f30014c014a2d3c3c350403010309340a3509340004040010001831183
11005040411041d351d361c361002040810081636040b110b144c154125422442200404052104213623372002040b223b2104040e200e2830373031040404353
4300531053533040a30093b3b3b32010501050932000d010d0542010111011832050611061d32000221022442010721072232050c210c2332050131013732010
531053532050b310b3b340f07000706480648000e0f0b110b1f2b122b1c1b171b131c121c1f0b1e0c190c180b160c100b11070f0e200e283e223e291e241e260
e210b000114480c450f480158025c055f055f045d025b0e4a1444050b010b064c064c010b240b064b054c0e3b0a3b063c033b0b2c042a012b0b1b071c011a0d0
b080a030c010801090308040808090b080d080f08021a02180419061808190b190d180e190128062909280d280f29033807390c390e390149044806440501210
12600260125431105333e282e22292e1b1d16102f0b2c033014390143154916422542264e224422392a2c2031353d080c0a3a0f32124913422349214e204b2c3
42e302f3a1f361e3e0c36080d003f003211341e211b2e0c2c08051029132b142b1d202c262d29262e242e21292e122d1d1d150800333330333f213c2c20320a0
9142122220a08122020220a06102e1e120a092f1e23220a06202d25220a0122202c220a0523242a22030f122e1c22030723252d22030d142b1d22030924272d2
20306112f1f1203072f1e2422030e21292e1207002f17122207062f1e2522070222212b22070521232a2b0a0a0e3e0f32114a12412245204d2e312148114e0e3
b0c3a030b0d3f0e37114021492e3d2f3e2f372041224611480004254f125124562656275a175c105e15460a0d0e211e231f2210311f2d0f240a033e2f223d213
33e25030d0e231e231f221d2d0e2303023e2c20333d240f0d043b083d073f04350f05333737363a3338333536080e1d102b132f162c172d132222070f1c12202
90f002b142e172d19271a261824132310261f181e010f161c1519181c1110201810122c0521152a092f0b241b261823112418070f18142519271a281b2617241
4231e1612080e161424120805241b26130a0b2615231423120a05231d1512030e1c252c22030b1e262e2208002b252b220a042d2c1d220a0c1d2e13220a08222
62d2400061c25192318261a230e0028132a122a130e08281829182a1200042813281200082819281200052c172c12080e1a1127120802271426120806251a271
2080e191f1812080a111f10120809181c161208082f052e02000817251f2300091721193e024400081d291e2e10371232000712341b32000a123715420005103
c0832000d08380042000f13322e3200022e3125420d0e26213c2200082b2c2a24050c073009300b3b0935050b09300740094b0b3d0832000e224126420001264
216420002164900420e03363439320d0b2c3523320805112a1622080f252b26220900084c0932090c08300a34060b3d4a1d400f4a3c47060e395c28511554065
6185829533853060b3e542f59006200062a172a140c00003d3f2c300000040b00003d303c354005440702362c362c3c333c3405090b09083f0e3f0214050d1e3
62f31374f1644070013101e323e323214060f02190b0b2b023212080225122912080027142714060c1e3c143625362e3405031a181a181e131e14050b1a1b1e1
02e102a1405032a132e182e182a14050b2a1b2e103e103a1405031028102814231424050b102b14202420202405032123242824282024050b202b24203420302
40503162816281a231a24050c162027202a2b1a240504262827282a232a24050c262037203a2b2a2405031c281c2810331034050c1c202d20203b103405032c2
82c2820332034050b2c203c20303b203404031f331d391d391f34040a2c3f2c3f2f392f3a03031d311b31193217361537153a1a3a1c391d351d3a030a2d382b3
8293b253b253e263139303d392d382c34050d153d1d302d3026340502253526352d322d320a0d364136420a0e1640064f1707254b354b3458345833573357325
332533352335234572457235623562252225326422641245c145b1b422f4d1a422c4326482b43274b25462545264725440c03284827482c432c4208023a423e4
3060a264a245a245208003c443c42080d115b31510803193108081b3108071831080b2c31080f2a3806042454235626562555275427532654245806063356345
73556375835553754365534520a000a5c3a590706254625442443224d144c18481a4c1c462644060b3549334f124226420802264b3644060c145810581a4c1f4
60c01284d144d174d18412c412742080b283b283207000f480f4207031f471f440b000a5c3b5c3560056203050d54085203080d580852030b0d5a08510904085
109080851090a085203010d52095109010852030d0d5d0952030f0d50195203021d52195203051d541952030719581d51090d085109001851090218510905185
109071852030a1d5b1952030d195e1d5203012d50295203032d542952030629572d5203092d5a2952030d295c2d5203003d5f2952030239523d5203053d54395
2030739573d520309385a3d52030c385c3d51090b1851090e1851090028510903285109062851090a2851090d285109003851090238510905385109073851090
93851090c385201030d540362010203610f52010603670e52010903690e510a000e510a030c510a070d510a090d52010b036c0e52010e036e0f5201011d50136
201031e54136201061e56136201091e5813610a0c0d510a0e0f510a011c510a031d510a061d510a091d52010b136b1f52010d136d1e52010f13602e520103236
22f52010523652f510a0b1f510a0c1d510a002e510a032e510a052e52010723682d52010a236a2f52010c236d2e52010f236f2e52010233613f52010433643e5
2010633673e52010933693d52010b336b3e510a082c510a0b2e510a0d2d510a0f2e510a023e510a043d510a073e510a093c510a0c3d510f0303610f0503610f0
002610f0a03610f080262030003610562030304630562030504650562030703680562030a046b05610f0d02610f021063030d026d046d05620302116115610f0
511610f0712610f0a11610f0c13610f0e12610f0121610f0422610f0623610f0923610f0b23620305126415620307136715620309126a1562030c146c1562030
e136f1562030122622562030423642562030624662562030924692562030b246b25610f0e24610f0033610f0334610f0534610f0833610f0a33610f0c3261030
e25620300346035610303356103053562030834683562030a346b3562030c336c3564060c362c322332233624070c062007200c3c0c34060c062702200320062
2060336233c340505392938293c253c2405053e293e2932353232050c392c3c22050c3f2c323405053439353938353832050c353c3834050b092708270c2b0c2
4050b0f270e27023b0234050409240c200c20082405040e24023002300f24050b053b08370837043405040430053008340837010700270c361c3810270027002
70025020f33310430036c336c38580d092d351c36112501260c300c300412351503052f12420c311c37552f340d0a2b1a21233c13341204052f15204401013b2
b372c363134340505392639253e463e45050e241c370c3100000004140206242a222a2c262d24110b2b1b212d202d2b292d29243c243c2d3e2f3e28403b40304
d2e3d253b243b2c203a203f1c212c291c00013a4131403040353e243e2b2f2a2f25313631304534453e4c0207305735493649363b353b372c362c373b373b374
93649325315062e16232823282c272d27243824382b3a2d3a244b254b2e392c39243724372d282d2823282d12120e281e2f113f113a233923353236323043324
33c443d4433433143353235323a223d1e2f14000721472b362b362e2905073536382937293a1c381c3c0730173b17382018033e1339203a20353e253e2f3c2e3
c264d274d2f3f2f3f25303530392339233d1304052e2c352c3722020624362b330401233c353c383304052a3c354c384201072c3721430405204c375c3458000
a3c0a39103e10341233123d1939193e030405242c371c3a1404052f1c370c3c052f12070925182b12070224162d12070b271f151207052a1a2812070c00260b2
20706012c03220708072601220706062510240600100c0e051e0b1104070e0d021103110e0d050706110812031d021d071204040418331633122311220804163
41332020410341d2201041a241622020413241225050114321432122111211232010212321e2208021c22192906080551165b165c19561953165d075a0757045
203021722132604070552165c195021571e4f0e42050216571f440501135b035e00541054060f1f31214d154a1344060d0630183e093c0731050a2a510509215
105053b5105002061050e21610506284105003551050e08410500294105021f31050a0a31050a1b4105021f5105030d41050a23510501294507020e14331c313
c3f4c0f4206040c2830220605013934220606073b392206080c3c3e220609014c3332060a064c3832060a0b4c3d32060c0f4c3242060c1f4c3742060c2f4c3b4
1010c3f42000c23272522000725262922000628282532000824342331000311320003113618320006183c1d32000c1d362e3200062e3f2b32000f2b303531000
03532000d203c2923000c2922372237220002372d2423000d203d20303532000c2921382200032e3025420000254b16420000254f1842000024432642000d2c3
230420003304335420003314634420004314731420005243b1a22000b1a291f2200091f2b1732000b17302a32000311391231000b252200090d2809220008082
b0622000b062f0922000f092d0e22000d0e2d0131000e053200063f293d2200093d2c3e22000c3e2c3232000c3238343200083437373100063a32000d094c064
2000c064f0442000f04421542000215431a4200031a451d4100081e42000b2722382208050f160b1208060b140a1208040a130d1208090e1a0b12080a0b19091
2080909180c12080d0d1f0912080f091d0812080d081c0b1208021c131912080318111712080117101b1208061b18181108081712080616141a12080a1b1c171
2080b171a1612080a16191812080f19102712080f161e1412080d151d17120803281526120804261323120802231127120809271a2412080a241722120807221
62612080e26113312080f231c2112080c211b2412080235143212080332123012080130103414040200050005080208040406040d040d08060804040e040f040
f060e060409000203020304000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0000000000000000000000000000000000071010000000000000000000000000000780840800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0020000000002000002000000000000000000000000020000000000000000000200000000000000000000000000000212121000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000212121000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0024000000000000000100000000080000000000000000000000002200000000000000000900000000000000000000212121000000000b00000000000000000000002200000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1111111100001111111111121212121212121212121111111111111111111111111111121212121212121212121212212121111111111111111111111111111111111111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2121212100002121212121121212121212121212122121212121212121212121212121121212121212121212121212212121212121212121212121212121212121212121212121212121212121212121000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
0102000008070090700b0700c0700e0700f070140001b0001c0001d00026000270002b0002b00009000090000c000130001c00030000000000000000000000000000000000000000000000000000000000000000
01090000130701f07026075260052600500000000000000019000000000000000000000001f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400
01030000315552d555265050050500505005050050500505005050050500505005050050500505005050050500505005050050500505005050050500505005050050500505005050050500505005050050500505
010800003c1203712036122331211e100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
011300001f00000000000001f0501f0502405024000000001e0501d050180501b0501d0501d0501d0501b0501b050180501b050180501b0501a0501a0501b0501b0521b0521b0521b0521b0521b0521b0021b002
011300001f50000500005002b5502b5503055024500005002a5502955024550275502955029550295502755027550245502755024550275502c5502c5502d5502d5522d5522d5522d5522d5522d5522d5022d502
011300000c3500c3550c3050a3500a3550a3050935009355053000835008355063500735007355003000535005355003000335003355003000635006355003500035000350003500035000350003550030000300
011300002700027000270001e0501f050180501e0501e052180502a005240001a0501b0501b0521b0550000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011300002750027500275002a5502b550245502a5502a552245502a505245002c5502d5502d5522d5550050000500005000050000500005000050000500005000050000500005000050000500005000050000500
011300000c3500c355073000a3500a355093000935009355063500835008355073500735007350073550030000300003000030000300003000030000300003000030000300003000030000300003000030000300
011000001557500500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
010200000805005050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010b000014070150701c050210501a000327051f00002100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
012f00000213002130021300213002130021300213002100041400414004140041400414004140041400010007150071500715007150071500715007150001000116001160011600116001160011600116001160
012f000015700157301573015730157301573015730007000070016740167401674016740167401674000700007001c7501c7501c7501c7501c7501c75000700007001f7601f7601f7601f7601f7601f7601f760
012f000000502005021d5301d5301d5321d5321d5320050200502005021f5401f5401f5421f5421f5420050200502005022255022550225522255222552005020050200502215602156021562215622156221562
012f000000502005021d502175301753217532175320050200502005020050219540195421954219542005020050200502005021a5501a5521a5521a552005020050200502005021c5601c5621c5621c5621c562
011000000233509335113350b3350233509335113350b33502335093350b3351133502335093350b33511335043350a335133350d335043350a335133350d335043350a3350d33513335043350a3350d33513335
01100000110230e0030e0030f0003462539300353003b300110230e0030e0030f000346253e3053e3053e305110230e0030e0030f0003462500000000000e003110230e0030e0030f00034625120030e00300000
011000000050000500005001d56423561235622356223562235622356124560245651d50000500005000050028500005002950500500285652950529565005002b5052b5052b5650050000500005000050000500
011000000733510335163350e3350733510335163350e335073350e3351033516335073350e33510335163350d3351333515335103350d3351333515335103350d3351033513335153350d335103351333515335
011000002d5652d5652b56500500005002850528565285652656500500005000050000500005000050000500005000050000500005002556526565285652b5652b5451f5412b5452b50500500005000050000500
0110000011023110033d6053d605346253d6053d6053d60511023110033d6053d605346250e0033e6050000011023110033d6053d6053462500000000000000011023346253d6053d605346253e6053462534625
011000002d560295502655023550215501d5501a550175501d5501a550215501d550265502355029550265502d5512d5502d5522d5522d5522d55229550265502b5512b5502b5522b5522b5522b5520050000500
011000002e5502b5502855026550225501f5501c5501a550225501f550265502255028550265502b550295502d5512d5552d5552d555000002f5002f5553055531555195512555531551000003d5553155331505
0110000011023110033d6053d605346253d6053d6053d60511023110033d6053d6053462500000000000000011023110033d6053d60534625000000000000000110233462534625346253e60511023346253e605
0110000011023110033d6053d605346253d6053d6053d60511023110033d6053d6051102334625346253460511023110033d6053d6053462500000000000000011023110033d6053d60534625346053460534625
0110000011023110033d6053d605346253d6053d6053d60511023110033d6053d605346252b6051c6050000011023110033d6053d6053462500000000000000011023110033d6053d60511023346153461534625
011000002d5502b5502d5521d504235012650226552245522655126552245001f55021550265502955028551285522855228552285522d502295052655022551225522255222552005000050000500005002d501
011000002e5502b5502e5521d5042350126502285522655228551285522450025550285502b5502e5552d5512d5522d5522d5522d5522d502295052b5502e5512e5522e5522e5522e502315512e5342b53428534
011000002d5502b5502d5521d504235012650226552245522655126552245001f55021550265502955028551285522855228552285522d502295052655029551295522955229552005000050000500005002d501
012a0000197651876517765187651e7651c7651a7651a7251a715187051e7051c7051a7050070500705007051a7051970518705197051e7051c705197051870517705187051e7051c7051a705007050070500705
010c0000181551615518155161551815516155181551615518155161551815516155221502215222152221551e1501e1501b1501b150161521615516105161050010000100001000010000100001000010000100
018000000116201662000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002
01ff00001f76200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002
01ff00002156200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01ff00001c56200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
04 04050644
04 07080944
00 0d0e0f10
04 21222324
00 11125344
00 14164344
01 11121344
00 141a1544
00 11121344
00 141b1544
00 11121744
00 14191844
00 11121344
00 141a1544
00 11121344
00 141b1544
00 11121c44
02 14191d44
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

