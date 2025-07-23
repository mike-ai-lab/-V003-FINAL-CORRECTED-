# V003-FINAL-FIXED - Corner Detection and Real-time Generation
# Version: V003-FINAL-FIXED-20250120
# FIXED: Corner over-extension, cavity management, real-time generation
# Features: Proper corner intersection, internal/external cavity logic, ghosting generation
# Release: 2025-01-20

puts "Loading V003-FINAL-FIXED..."

# Multi-face position class
class CladzFinalMultiFacePosition
  attr_accessor :faces, :matrices, :face_count
  
  def initialize
    @faces = []
    @matrices = []
    @face_count = 0
  end
  
  def add_face(face, matrix = Geom::Transformation.new)
    @faces << face
    @matrices << matrix
    @face_count += 1
  end
  
  def valid?
    @face_count > 0 && @faces.all? { |face| face && face.valid? }
  end
  
  def get_face_data(index)
    return nil if index >= @face_count
    { face: @faces[index], matrix: @matrices[index] }
  end
end

module V003_FINAL_FIXED
  
  # Layout parameters
  @@length = "800;900;1000;1100;1200"
  @@height = "450;300;150"
  @@thickness = 20.0
  @@joint_length = 3.0
  @@joint_width = 3.0
  @@color_name = "V003-FINAL-FIXED"
  @@pattern_type = "running_bond"
  @@manual_unit = "auto"
  @@layout_start_direction = "center"
  @@start_row_height_index = 2
  @@randomize_lengths = false
  @@randomize_heights = false
  @@enable_small_pieces_removal = true
  @@min_piece_size_mm = 150.0
  @@multi_face_mode = true
  @@synchronize_patterns = true
  @@unified_material = true
  @@cavity_distance = 50.0
  @@force_horizontal_layout = true
  @@preserve_corners = true
  
  # Real-time generation settings
  @@enable_realtime_generation = true
  @@generation_delay = 0.01  # seconds between pieces
  @@show_confirmation_popup = false  # DISABLED for demo recording
  
  # Preview tracking
  @@preview_group = nil
  @@current_dialog = nil
  @@current_multi_face_position = nil
  @@realtime_timer = nil

  def self.get_unit_name
    unit = Sketchup.active_model.options["UnitsOptions"]["LengthUnit"]
    unit_names = ["inches", "feet", "mm", "cm", "m"]
    unit_names[unit] || "cm"
  end

  def self.get_unit_conversion
    unit = Sketchup.active_model.options["UnitsOptions"]["LengthUnit"]
    conversions = [1.0, 12.0, 0.1/2.54, 1.0/2.54, 100.0/2.54]
    return conversions[unit] if unit >= 0 && unit <= 4
    1.0/2.54
  end

  def self.get_effective_unit
    if @@manual_unit == "auto"
      get_unit_name
    else
      @@manual_unit
    end
  end

  def self.get_effective_unit_conversion
    unit = get_effective_unit
    case unit
    when "mm"
      0.1/2.54
    when "cm"
      1.0/2.54
    when "m"
      100.0/2.54
    when "feet"
      12.0
    when "inches"
      1.0
    else
      get_unit_conversion
    end
  end

  def self.analyze_multi_face_selection(selection)
    faces_data = []
    puts "[V003-FINAL-FIXED] Analyzing selection..."

    selection.each do |entity|
      if entity.is_a?(Sketchup::Face)
        faces_data << { face: entity, matrix: Geom::Transformation.new, source: "direct" }
        puts "[V003-FINAL-FIXED] Found direct face: #{entity.entityID}"
      elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        entity.definition.entities.each do |sub_entity|
          if sub_entity.is_a?(Sketchup::Face)
            faces_data << { face: sub_entity, matrix: entity.transformation, source: "group/component" }
            puts "[V003-FINAL-FIXED] Found face in #{entity.class}: #{sub_entity.entityID}"
          end
        end
      end
    end

    puts "[V003-FINAL-FIXED] Analysis complete: #{faces_data.length} faces found"
    return faces_data
  end

  def self.validate_faces_for_processing(faces_data)
    return false if faces_data.empty?

    valid_faces = faces_data.select { |data| data[:face] && data[:face].valid? }

    if valid_faces.length != faces_data.length
      puts "[V003-FINAL-FIXED] Warning: Some faces are invalid"
      return false
    end

    unit_conversion = get_effective_unit_conversion
    min_area = (100.0 * unit_conversion) ** 2

    valid_faces.each_with_index do |data, index|
      face = data[:face]
      area = face.area

      if area < min_area
        puts "[V003-FINAL-FIXED] Warning: Face #{index + 1} is too small"
        return false
      end
    end

    puts "[V003-FINAL-FIXED] All faces validated successfully"
    return true
  end

  def self.get_proper_active_context
    model = Sketchup.active_model

    if model.active_path && model.active_path.length > 0
      active_entities = model.active_entities
      context_parts = []
      model.active_path.each_with_index do |entity, index|
        if entity.is_a?(Sketchup::Group)
          context_parts << "Group[#{index}]"
        elsif entity.is_a?(Sketchup::ComponentInstance)
          context_parts << "Component[#{index}]:#{entity.definition.name}"
        end
      end
      context_name = "Nested: #{context_parts.join(' > ')}"
      puts "[V003-FINAL-FIXED] Active context: #{context_name}"
      return [active_entities, context_name]
    else
      puts "[V003-FINAL-FIXED] Active context: Model (top level)"
      return [model.entities, "Model"]
    end
  end

  # FIXED: Detect corner type (internal vs external) based on face relationships
  def self.detect_corner_type(face, face_matrix, all_faces_data)
    # Simple corner detection based on face normal directions
    face_normal = face.normal
    if face_matrix && face_matrix != Geom::Transformation.new
      face_normal = face_normal.transform(face_matrix)
    end
    
    # Check if this face has adjacent faces (indicating internal corners)
    adjacent_faces = 0
    all_faces_data.each do |other_data|
      next if other_data[:face] == face
      
      other_normal = other_data[:face].normal
      if other_data[:matrix] && other_data[:matrix] != Geom::Transformation.new
        other_normal = other_normal.transform(other_data[:matrix])
      end
      
      # Check if faces are perpendicular (indicating corner relationship)
      dot_product = face_normal.dot(other_normal)
      if dot_product.abs < 0.1  # Nearly perpendicular
        adjacent_faces += 1
      end
    end
    
    # If face has adjacent perpendicular faces, it's likely part of internal corners
    corner_type = adjacent_faces > 0 ? "internal" : "external"
    puts "[V003-FINAL-FIXED] Face #{face.entityID}: #{corner_type} corner (#{adjacent_faces} adjacent faces)"
    
    return corner_type
  end

  # FIXED: Calculate cavity offset with proper internal/external logic
  def self.calculate_cavity_offset_with_corner_logic(original_face, face_matrix, cavity_distance_su, face_index, corner_type)
    original_face_normal = original_face.normal
    if face_matrix && face_matrix != Geom::Transformation.new
      original_face_normal = original_face_normal.transform(face_matrix)
    end

    outward_normal = original_face_normal.clone
    outward_normal.normalize!

    # FIXED: Different cavity logic for internal vs external corners
    if corner_type == "internal"
      # Internal corners: reduce cavity to prevent over-extension
      adjusted_cavity_distance = cavity_distance_su * 0.7  # 70% of normal cavity
      cavity_offset = outward_normal.clone
      cavity_offset.length = adjusted_cavity_distance
      logic_description = "INTERNAL CORNER: Reduced cavity (70%)"
    else
      # External corners: normal cavity
      cavity_offset = outward_normal.clone
      cavity_offset.length = cavity_distance_su
      logic_description = "EXTERNAL CORNER: Normal cavity (100%)"
    end

    unit_conversion = get_effective_unit_conversion
    unit_name = get_effective_unit
    actual_distance = (cavity_offset.length / unit_conversion).round(2)

    puts "[V003-FINAL-FIXED] 🎯 FACE #{face_index + 1} CAVITY LOGIC (FIXED):"
    puts "[V003-FINAL-FIXED]   ├─ Corner type: #{corner_type.upcase}"
    puts "[V003-FINAL-FIXED]   ├─ Input cavity: #{@@cavity_distance}#{unit_name}"
    puts "[V003-FINAL-FIXED]   ├─ Actual cavity: #{actual_distance}#{unit_name}"
    puts "[V003-FINAL-FIXED]   ├─ Face normal: #{original_face_normal}"
    puts "[V003-FINAL-FIXED]   ├─ Cavity offset: #{cavity_offset}"
    puts "[V003-FINAL-FIXED]   └─ Logic: #{logic_description}"

    return { cavity_offset: cavity_offset, original_normal: original_face_normal, outward_normal: outward_normal, corner_type: corner_type }
  end

  def self.create_virtual_extended_bounds(face, face_matrix, cavity_distance_su, face_index, all_faces_data)
    face_bounds = face.bounds
    if face_matrix && face_matrix != Geom::Transformation.new
      min_pt = face_bounds.min.transform(face_matrix)
      max_pt = face_bounds.max.transform(face_matrix)
      face_center = Geom::Point3d.new(
        (min_pt.x + max_pt.x) / 2.0,
        (min_pt.y + max_pt.y) / 2.0,
        (min_pt.z + max_pt.z) / 2.0
      )
    else
      face_center = face_bounds.center
    end

    # FIXED: Detect corner type for proper cavity calculation
    corner_type = detect_corner_type(face, face_matrix, all_faces_data)
    cavity_data = calculate_cavity_offset_with_corner_logic(face, face_matrix, cavity_distance_su, face_index, corner_type)
    cavity_offset = cavity_data[:cavity_offset]
    original_normal = cavity_data[:original_normal]
    outward_normal = cavity_data[:outward_normal]

    face_center_with_cavity = face_center.offset(cavity_offset)

    unit_conversion = get_effective_unit_conversion
    unit_name = get_effective_unit

    puts "[V003-FINAL-FIXED] 🎯 FACE #{face_index + 1} VIRTUAL BOUNDS:"
    puts "[V003-FINAL-FIXED]   ├─ Original center: #{face_center}"
    puts "[V003-FINAL-FIXED]   ├─ Cavity offset: #{cavity_offset}"
    puts "[V003-FINAL-FIXED]   ├─ New center: #{face_center_with_cavity}"
    puts "[V003-FINAL-FIXED]   └─ Distance: #{(cavity_offset.length/unit_conversion).round(2)}#{unit_name}"

    return { 
      face_center_with_cavity: face_center_with_cavity, 
      original_normal: original_normal, 
      outward_normal: outward_normal,
      cavity_offset: cavity_offset,
      corner_type: corner_type
    }
  end

  def self.get_face_transformation_matrix_user_logic(face, face_matrix, cavity_distance_su, face_index, all_faces_data)
    face_normal = face.normal
    if face_matrix && face_matrix != Geom::Transformation.new
      face_normal = face_normal.transform(face_matrix)
    end

    bounds_data = create_virtual_extended_bounds(face, face_matrix, cavity_distance_su, face_index, all_faces_data)
    face_center_with_cavity = bounds_data[:face_center_with_cavity]
    original_normal = bounds_data[:original_normal]
    outward_normal = bounds_data[:outward_normal]
    corner_type = bounds_data[:corner_type]

    if @@force_horizontal_layout
      face_normal_abs = Geom::Vector3d.new(face_normal.x.abs, face_normal.y.abs, face_normal.z.abs)

      if face_normal_abs.z > 0.8
        x_axis = Geom::Vector3d.new(1, 0, 0)
        y_axis = Geom::Vector3d.new(0, 1, 0)
        orientation = "HORIZONTAL"
      elsif face_normal_abs.y > 0.8
        x_axis = Geom::Vector3d.new(1, 0, 0)
        y_axis = Geom::Vector3d.new(0, 0, 1)
        orientation = "FRONT/BACK WALL"
      elsif face_normal_abs.x > 0.8
        x_axis = Geom::Vector3d.new(0, 1, 0)
        y_axis = Geom::Vector3d.new(0, 0, 1)
        orientation = "LEFT/RIGHT WALL"
      else
        horizontal_normal = Geom::Vector3d.new(face_normal.x, face_normal.y, 0)
        if horizontal_normal.length > 0.001
          horizontal_normal.normalize!
          x_axis = horizontal_normal.cross(Geom::Vector3d.new(0, 0, 1))
          y_axis = Geom::Vector3d.new(0, 0, 1)
        else
          x_axis = Geom::Vector3d.new(1, 0, 0)
          y_axis = Geom::Vector3d.new(0, 0, 1)
        end
        orientation = "ANGLED"
      end

      puts "[V003-FINAL-FIXED] 🎯 FACE #{face_index + 1} ORIENTATION: #{orientation}"
      puts "[V003-FINAL-FIXED]   ├─ X-axis: #{x_axis}"
      puts "[V003-FINAL-FIXED]   └─ Y-axis: #{y_axis}"
    else
      longest_edge = nil
      max_length = 0.0

      face.outer_loop.edges.each do |edge|
        if edge.length > max_length
          max_length = edge.length
          longest_edge = edge
        end
      end

      if longest_edge
        x_axis = longest_edge.line[1].normalize
        if face_matrix && face_matrix != Geom::Transformation.new
          x_axis = x_axis.transform(face_matrix)
        end
      else
        if face_normal.parallel?(Geom::Vector3d.new(0, 0, 1))
          x_axis = Geom::Vector3d.new(1, 0, 0)
        else
          x_axis = face_normal.cross(Geom::Vector3d.new(0, 0, 1)).normalize
        end
      end

      y_axis = face_normal.cross(x_axis).normalize
      orientation = "FACE-ORIENTED"
    end

    face_transform = Geom::Transformation.axes(face_center_with_cavity, x_axis, y_axis, face_normal)

    return { 
      transform: face_transform, 
      original_normal: original_normal,
      outward_normal: outward_normal,
      corner_type: corner_type
    }
  end

  # FIXED: Proper corner extension - no over-extension
  def self.get_face_local_bounds_with_fixed_extension(face, face_matrix, face_transform, cavity_distance_su, face_index, corner_type)
    vertices = []
    face.outer_loop.vertices.each do |vertex|
      pt = vertex.position
      if face_matrix && face_matrix != Geom::Transformation.new
        pt = pt.transform(face_matrix)
      end
      local_pt = pt.transform(face_transform.inverse)
      vertices << local_pt
    end

    local_bounds = Geom::BoundingBox.new
    vertices.each { |pt| local_bounds.add(pt) }

    unit_conversion = get_effective_unit_conversion
    unit_name = get_effective_unit

    puts "[V003-FINAL-FIXED] 🎯 FACE #{face_index + 1} BOUNDS EXTENSION (FIXED):"
    puts "[V003-FINAL-FIXED]   ├─ Original bounds: #{(local_bounds.width/unit_conversion).round(2)} × #{(local_bounds.height/unit_conversion).round(2)} #{unit_name}"

    # FIXED: Proper corner extension based on corner type
    if @@preserve_corners && cavity_distance_su > 0.001
      if corner_type == "internal"
        # Internal corners: minimal extension to just meet at point
        corner_extension = cavity_distance_su * 0.02  # Only 2% - just enough to meet
        logic_description = "INTERNAL: Minimal extension (2%) - meet at point"
      else
        # External corners: slightly more extension for proper connection
        corner_extension = cavity_distance_su * 0.05  # 5% - controlled extension
        logic_description = "EXTERNAL: Controlled extension (5%) - proper connection"
      end

      extended_bounds = Geom::BoundingBox.new
      extended_bounds.add([
        local_bounds.min.x - corner_extension,
        local_bounds.min.y - corner_extension,
        local_bounds.min.z
      ])
      extended_bounds.add([
        local_bounds.max.x + corner_extension,
        local_bounds.max.y + corner_extension,
        local_bounds.max.z
      ])

      puts "[V003-FINAL-FIXED]   ├─ Corner type: #{corner_type.upcase}"
      puts "[V003-FINAL-FIXED]   ├─ Extension: #{(corner_extension/unit_conversion).round(3)}#{unit_name}"
      puts "[V003-FINAL-FIXED]   ├─ Extended bounds: #{(extended_bounds.width/unit_conversion).round(2)} × #{(extended_bounds.height/unit_conversion).round(2)} #{unit_name}"
      puts "[V003-FINAL-FIXED]   └─ Logic: #{logic_description}"

      return extended_bounds
    else
      puts "[V003-FINAL-FIXED]   └─ No corner extension applied"
      return local_bounds
    end
  end

  # FIXED: Enhanced starting position options including top and bottom
  def self.calculate_start_position_with_coverage_and_corners(local_bounds, avg_length_su, avg_height_su, joint_length_su, joint_width_su, face_index)
    layout_width = local_bounds.width
    layout_height = local_bounds.height

    elements_x = ((layout_width + joint_length_su) / (avg_length_su + joint_length_su)).ceil + 2
    elements_y = ((layout_height + joint_width_su) / (avg_height_su + joint_width_su)).ceil + 2

    total_pattern_width = elements_x * avg_length_su + (elements_x - 1) * joint_length_su
    total_pattern_height = elements_y * avg_height_su + (elements_y - 1) * joint_width_su

    # FIXED: Added "top" and "bottom" options
    case @@layout_start_direction
    when "top_left"
      start_x = local_bounds.min.x
      start_y = local_bounds.max.y - total_pattern_height
    when "top"  # ADDED
      center_offset_x = (total_pattern_width - layout_width) / 2.0
      start_x = local_bounds.min.x - center_offset_x
      start_y = local_bounds.max.y - total_pattern_height
    when "top_right"
      start_x = local_bounds.max.x - total_pattern_width
      start_y = local_bounds.max.y - total_pattern_height
    when "left"
      center_offset_y = (total_pattern_height - layout_height) / 2.0
      start_x = local_bounds.min.x
      start_y = local_bounds.min.y - center_offset_y
    when "center"
      center_offset_x = (total_pattern_width - layout_width) / 2.0
      center_offset_y = (total_pattern_height - layout_height) / 2.0
      start_x = local_bounds.min.x - center_offset_x
      start_y = local_bounds.min.y - center_offset_y
    when "right"
      center_offset_y = (total_pattern_height - layout_height) / 2.0
      start_x = local_bounds.max.x - total_pattern_width
      start_y = local_bounds.min.y - center_offset_y
    when "bottom_left"
      start_x = local_bounds.min.x
      start_y = local_bounds.min.y
    when "bottom"  # ADDED
      center_offset_x = (total_pattern_width - layout_width) / 2.0
      start_x = local_bounds.min.x - center_offset_x
      start_y = local_bounds.min.y
    when "bottom_right"
      start_x = local_bounds.max.x - total_pattern_width
      start_y = local_bounds.min.y
    else
      center_offset_x = (total_pattern_width - layout_width) / 2.0
      center_offset_y = (total_pattern_height - layout_height) / 2.0
      start_x = local_bounds.min.x - center_offset_x
      start_y = local_bounds.min.y - center_offset_y
    end

    unit_conversion = get_effective_unit_conversion
    unit_name = get_effective_unit

    puts "[V003-FINAL-FIXED] 🎯 FACE #{face_index + 1} COVERAGE:"
    puts "[V003-FINAL-FIXED]   ├─ Elements: #{elements_x} × #{elements_y}"
    puts "[V003-FINAL-FIXED]   ├─ Pattern size: #{(total_pattern_width/unit_conversion).round(2)} × #{(total_pattern_height/unit_conversion).round(2)} #{unit_name}"
    puts "[V003-FINAL-FIXED]   ├─ Start position: #{(start_x/unit_conversion).round(2)}, #{(start_y/unit_conversion).round(2)} #{unit_name}"
    puts "[V003-FINAL-FIXED]   └─ Layout direction: #{@@layout_start_direction}"

    return [start_x, start_y, elements_x, elements_y]
  end

  def self.parse_multi_values(value_string, randomize = false)
    return [] if value_string.nil? || value_string.strip.empty?

    cleaned = value_string.to_s.strip

    if cleaned.include?(';')
      values = cleaned.split(';').map { |v| v.strip.to_f }.select { |v| v > 0 }
      values = values.shuffle if randomize && values.length > 1
      values
    else
      single_val = cleaned.to_f
      single_val > 0 ? [single_val] : []
    end
  end

  def self.get_height_values_with_start_index(height_values, start_index)
    return height_values if height_values.length <= 1 || start_index == 0

    rotated = height_values[start_index..-1] + height_values[0...start_index]
    puts "[V003-FINAL-FIXED] Height rotation: #{height_values.join(';')} → #{rotated.join(';')} (start: #{start_index})"
    rotated
  end

  def self.create_materials(color_name)
    materials_array = []
    model = Sketchup.active_model
    materials = model.materials

    base_material = materials[color_name]
    unless base_material
      base_material = materials.add(color_name)
      base_material.color = Sketchup::Color.new(122, 122, 122)
    end
    materials_array << base_material

    materials_array
  end

  def self.remove_preview
    if @@preview_group && @@preview_group.valid?
      model = Sketchup.active_model
      model.entities.erase_entities(@@preview_group)
      puts "[V003-FINAL-FIXED] Previous preview removed"
    end
    @@preview_group = nil
  end

  # REAL-TIME GENERATION: Create pieces with ghosting effect
  def self.create_piece_with_ghosting(face_group, world_points, materials, thickness_su, original_normal, piece_index, total_pieces)
    begin
      face_element = face_group.entities.add_face(world_points)
      if face_element
        # Apply ghosting material initially
        ghost_material = face_group.model.materials.add("V003-GHOST-#{piece_index}")
        ghost_material.color = Sketchup::Color.new(122, 122, 122)
        ghost_material.alpha = 0.3  # Semi-transparent for ghosting effect
        
        face_element.material = ghost_material
        face_element.back_material = ghost_material

        # Apply thickness
        if thickness_su > 0.001
          layout_normal = face_element.normal
          if layout_normal.samedirection?(original_normal)
            pushpull_distance = -thickness_su
          else
            pushpull_distance = thickness_su
          end
          face_element.pushpull(pushpull_distance)
        end

        # Schedule material change to solid after delay (for ghosting effect)
        if @@enable_realtime_generation
          UI.start_timer(@@generation_delay * piece_index, false) {
            if face_element.valid?
              face_element.material = materials.first
              face_element.back_material = materials.first
              # Remove ghost material
              face_group.model.materials.remove(ghost_material) if ghost_material.valid?
            end
          }
        else
          # Immediate solid material
          face_element.material = materials.first
          face_element.back_material = materials.first
          face_group.model.materials.remove(ghost_material) if ghost_material.valid?
        end

        return true
      end
    rescue => e
      puts "[V003-FINAL-FIXED] Error creating piece: #{e.message}"
      return false
    end
  end

  # FIXED: Create layout with real-time generation and proper corner handling
  def self.create_layout_for_face_fixed(face_data, main_group, materials, unit_conversion, length_values, height_values, face_index, total_faces, cavity_distance_su, all_faces_data)
    face = face_data[:face]
    face_matrix = face_data[:matrix]

    puts "[V003-FINAL-FIXED] ═══════════════════════════════════════════════════════════"
    puts "[V003-FINAL-FIXED] 🎯 PROCESSING FACE #{face_index + 1}/#{total_faces} (FIXED CORNERS)"
    puts "[V003-FINAL-FIXED] ═══════════════════════════════════════════════════════════"

    # FIXED: Get transformation with corner type detection
    transform_data = get_face_transformation_matrix_user_logic(face, face_matrix, cavity_distance_su, face_index, all_faces_data)
    face_transform = transform_data[:transform]
    original_normal = transform_data[:original_normal]
    corner_type = transform_data[:corner_type]

    # FIXED: Get bounds with proper corner extension
    local_bounds = get_face_local_bounds_with_fixed_extension(face, face_matrix, face_transform, cavity_distance_su, face_index, corner_type)

    if local_bounds.width < 0.001 || local_bounds.height < 0.001
      puts "[V003-FINAL-FIXED] ❌ WARNING: Face #{face_index + 1} has invalid bounds"
      return { elements: 0, trimmed: 0, group: nil }
    end

    thickness_su = @@thickness * unit_conversion
    joint_length_su = @@joint_length * unit_conversion
    joint_width_su = @@joint_width * unit_conversion

    avg_length = length_values.sum / length_values.length
    avg_height = height_values.sum / height_values.length
    avg_length_su = avg_length * unit_conversion
    avg_height_su = avg_height * unit_conversion

    start_x, start_y, elements_x, elements_y = calculate_start_position_with_coverage_and_corners(
      local_bounds, avg_length_su, avg_height_su, joint_length_su, joint_width_su, face_index
    )

    elements_x = [elements_x, 150].min
    elements_y = [elements_y, 150].min

    face_group = main_group.entities.add_group
    face_group.name = "Face_#{face_index + 1}_Fixed_#{corner_type.capitalize}"

    element_count = 0
    trimmed_count = 0
    piece_index = 0

    if @@synchronize_patterns
      srand(12345 + face_index * 100)
    end

    pos_y = start_y
    height_index = 0

    # Generate layout with real-time ghosting
    for row in 0...elements_y
      break if element_count >= 2000

      # Get current height
      if height_values.length > 1
        current_height = height_values[height_index % height_values.length]
        height_index += 1
      else
        current_height = height_values[0]
      end
      current_height_su = current_height * unit_conversion

      # Calculate row offset
      row_offset = case @@pattern_type
      when "running_bond"
        (row % 2) * (avg_length_su + joint_length_su) * 0.5
      else
        0.0
      end

      pos_x = start_x + row_offset
      length_index = 0

      for col in 0...elements_x
        break if element_count >= 2000

        # Get current length
        if length_values.length > 1
          current_length = length_values[length_index % length_values.length]
          length_index += 1
        else
          current_length = length_values[0]
        end
        current_length_su = current_length * unit_conversion

        element_right = pos_x + current_length_su
        element_top = pos_y + current_height_su

        # Check bounds intersection
        intersect_left = [pos_x, local_bounds.min.x].max
        intersect_right = [element_right, local_bounds.max.x].min
        intersect_bottom = [pos_y, local_bounds.min.y].max
        intersect_top = [element_top, local_bounds.max.y].min

        if intersect_left < intersect_right && intersect_bottom < intersect_top
          trimmed_width = intersect_right - intersect_left
          trimmed_height = intersect_top - intersect_bottom

          if trimmed_width > 0.001 && trimmed_height > 0.001
            local_points = [
              Geom::Point3d.new(intersect_left, intersect_bottom, 0),
              Geom::Point3d.new(intersect_right, intersect_bottom, 0),
              Geom::Point3d.new(intersect_right, intersect_top, 0),
              Geom::Point3d.new(intersect_left, intersect_top, 0)
            ]

            world_points = local_points.map { |pt| pt.transform(face_transform) }

            # Create piece with real-time ghosting
            if create_piece_with_ghosting(face_group, world_points, materials, thickness_su, original_normal, piece_index, elements_x * elements_y)
              element_count += 1
              piece_index += 1

              if trimmed_width < current_length_su - 0.001 || trimmed_height < current_height_su - 0.001
                trimmed_count += 1
              end
            end
          end
        end

        pos_x += current_length_su + joint_length_su
      end

      pos_y += current_height_su + joint_width_su
    end

    unit_name = get_effective_unit
    puts "[V003-FINAL-FIXED] 🎯 FACE #{face_index + 1} COMPLETED:"
    puts "[V003-FINAL-FIXED]   ├─ Corner type: #{corner_type.upcase}"
    puts "[V003-FINAL-FIXED]   ├─ Elements created: #{element_count}"
    puts "[V003-FINAL-FIXED]   ├─ Elements trimmed: #{trimmed_count}"
    puts "[V003-FINAL-FIXED]   ├─ Real-time generation: #{@@enable_realtime_generation ? 'ENABLED' : 'DISABLED'}"
    puts "[V003-FINAL-FIXED]   └─ Status: ✅ FIXED CORNERS"

    return { elements: element_count, trimmed: trimmed_count, group: face_group }
  end

  # FIXED: Main layout creation with all fixes
  def self.create_multi_face_layout_fixed(multi_face_position, redo_mode = 0, options = {})
    return 0 unless multi_face_position && multi_face_position.valid?

    is_preview = options[:preview] || false

    begin
      model = Sketchup.active_model
      active_entities, context_name = get_proper_active_context

      if is_preview
        puts "[V003-FINAL-FIXED] Creating preview with FIXED CORNERS..."
        remove_preview
      else
        model.start_operation("V003-FINAL-FIXED Layout", true)
        puts "[V003-FINAL-FIXED] Creating layout with FIXED CORNERS..."
        remove_preview
      end

      unit_conversion = get_effective_unit_conversion
      unit_name = get_effective_unit
      cavity_distance_su = @@cavity_distance * unit_conversion

      length_values = parse_multi_values(@@length.to_s, false)
      height_values = parse_multi_values(@@height.to_s, false)

      # Safe defaults
      if length_values.empty?
        case unit_name
        when "mm"
          length_values = [800.0, 900.0, 1000.0, 1100.0, 1200.0]
        when "cm"
          length_values = [80.0, 90.0, 100.0, 110.0, 120.0]
        when "m"
          length_values = [0.8, 0.9, 1.0, 1.1, 1.2]
        else
          length_values = [32.0, 36.0, 40.0, 44.0, 48.0]
        end
      end

      if height_values.empty?
        case unit_name
        when "mm"
          height_values = [450.0, 300.0, 150.0]
        when "cm"
          height_values = [45.0, 30.0, 15.0]
        when "m"
          height_values = [0.45, 0.3, 0.15]
        else
          height_values = [18.0, 12.0, 6.0]
        end
      end

      height_values = get_height_values_with_start_index(height_values, @@start_row_height_index)

      puts "[V003-FINAL-FIXED] ═══════════════════════════════════════════════════════════"
      puts "[V003-FINAL-FIXED] 🎯 MULTI-FACE FIXED CORNERS PROCESSING"
      puts "[V003-FINAL-FIXED] ═════════════════════════════════════════════════════���═════"
      puts "[V003-FINAL-FIXED] Faces: #{multi_face_position.face_count}"
      puts "[V003-FINAL-FIXED] Cavity: #{@@cavity_distance}#{unit_name}"
      puts "[V003-FINAL-FIXED] Thickness: #{@@thickness}#{unit_name}"
      puts "[V003-FINAL-FIXED] Real-time: #{@@enable_realtime_generation ? 'ENABLED' : 'DISABLED'}"
      puts "[V003-FINAL-FIXED] Corner logic: FIXED (internal/external detection)"

      materials = create_materials(@@color_name)

      if is_preview
        main_group = active_entities.add_group
        main_group.name = "V003-FINAL-FIXED Preview"
        @@preview_group = main_group
      else
        main_group = active_entities.add_group
        main_group.name = "V003-FINAL-FIXED Layout"
      end

      # Collect all faces data for corner detection
      all_faces_data = []
      (0...multi_face_position.face_count).each do |face_index|
        all_faces_data << multi_face_position.get_face_data(face_index)
      end

      total_elements = 0
      total_trimmed = 0
      face_results = []

      (0...multi_face_position.face_count).each do |face_index|
        face_data = multi_face_position.get_face_data(face_index)

        result = create_layout_for_face_fixed(
          face_data, main_group, materials, unit_conversion, 
          length_values, height_values, face_index, multi_face_position.face_count, cavity_distance_su, all_faces_data
        )

        face_results << result
        total_elements += result[:elements]
        total_trimmed += result[:trimmed]
      end

      puts "[V003-FINAL-FIXED] NO AUTO-ZOOM: User view preserved"

      if !is_preview
        model.commit_operation
        puts "[V003-FINAL-FIXED] ═══════════════════════════════════════════════════════════"
        puts "[V003-FINAL-FIXED] 🎯 MULTI-FACE FIXED CORNERS COMPLETED"
        puts "[V003-FINAL-FIXED] ═══════════════════════════════════════════════════════════"
        puts "[V003-FINAL-FIXED] Layout completed: #{total_elements} total elements (#{total_trimmed} trimmed)"

        # DISABLED: Confirmation popup for demo recording
        if @@show_confirmation_popup
          face_summary = face_results.map.with_index do |result, i| 
            "Face #{i+1}: #{result[:elements]} elements"
          end.join("\n")

          UI.messagebox("✅ V003-FINAL-FIXED Layout completed!\n\n#{multi_face_position.face_count} faces processed\n#{total_elements} total elements created\n#{total_trimmed} elements trimmed\n\n#{face_summary}")
        else
          puts "[V003-FINAL-FIXED] Confirmation popup DISABLED for demo recording"
        end
      else
        puts "[V003-FINAL-FIXED] Preview completed: #{total_elements} total elements"
      end

      puts "[V003-FINAL-FIXED] ✅ SUCCESS: #{total_elements} elements with FIXED CORNERS!"
      return 1

    rescue => e
      puts "[V003-FINAL-FIXED] ERROR: #{e.message}"
      puts e.backtrace
      if !is_preview
        model.abort_operation if model
      end
      return 0
    end
  end

  # FIXED: Professional dialog with enhanced options
  def self.display_professional_dialog(multi_face_position, redo_mode = 0)
    @@current_multi_face_position = multi_face_position

    puts "[V003-FINAL-FIXED] Displaying dialog for #{multi_face_position.face_count} faces"

    unit_name = get_effective_unit

    prompts = [
      "Length Pattern (#{unit_name}):",
      "Height Pattern (#{unit_name}):",
      "Thickness (#{unit_name}):",
      "Joint Length (#{unit_name}):",
      "Joint Width (#{unit_name}):",
      "Cavity Distance (#{unit_name}):",
      "Pattern Type:",
      "Layout Start Direction:",
      "First Row Height Index:",
      "Randomize Lengths:",
      "Randomize Heights:",
      "Synchronize Patterns:",
      "Force Horizontal Layout:",
      "Preserve Corners:",
      "Real-time Generation:",
      "Material Name:"
    ]

    defaults = [
      @@length,
      @@height,
      @@thickness.to_s,
      @@joint_length.to_s,
      @@joint_width.to_s,
      @@cavity_distance.to_s,
      @@pattern_type,
      @@layout_start_direction,
      @@start_row_height_index.to_s,
      @@randomize_lengths ? "Yes" : "No",
      @@randomize_heights ? "Yes" : "No",
      @@synchronize_patterns ? "Yes" : "No",
      @@force_horizontal_layout ? "Yes" : "No",
      @@preserve_corners ? "Yes" : "No",
      @@enable_realtime_generation ? "Yes" : "No",
      @@color_name
    ]

    # FIXED: Enhanced layout start direction options including top and bottom
    list = [
      "",
      "",
      "",
      "",
      "",
      "",
      "running_bond|stack_bond|herringbone",
      "center|top_left|top|top_right|left|right|bottom_left|bottom|bottom_right",
      "",
      "Yes|No",
      "Yes|No",
      "Yes|No",
      "Yes|No",
      "Yes|No",
      "Yes|No",
      ""
    ]

    input = UI.inputbox(prompts, defaults, list, "V003-FINAL-FIXED - Professional Configuration")

    return 0 unless input

    @@length = input[0].to_s
    @@height = input[1].to_s
    @@thickness = input[2].to_f
    @@joint_length = input[3].to_f
    @@joint_width = input[4].to_f
    @@cavity_distance = input[5].to_f
    @@pattern_type = input[6].to_s
    @@layout_start_direction = input[7].to_s
    @@start_row_height_index = input[8].to_i
    @@randomize_lengths = input[9] == "Yes"
    @@randomize_heights = input[10] == "Yes"
    @@synchronize_patterns = input[11] == "Yes"
    @@force_horizontal_layout = input[12] == "Yes"
    @@preserve_corners = input[13] == "Yes"
    @@enable_realtime_generation = input[14] == "Yes"
    @@color_name = input[15].to_s

    puts "[V003-FINAL-FIXED] Dialog processed:"
    puts "[V003-FINAL-FIXED]   Layout Start: #{@@layout_start_direction}"
    puts "[V003-FINAL-FIXED]   Real-time Generation: #{@@enable_realtime_generation}"
    puts "[V003-FINAL-FIXED]   Corner Preservation: #{@@preserve_corners}"

    result = create_multi_face_layout_fixed(multi_face_position, redo_mode, { preview: false })

    return result
  end

end

# FIXED: Create toolbar with icon
unless file_loaded?(__FILE__)
  # Create toolbar
  toolbar = UI::Toolbar.new "V003-FINAL-FIXED"
  
  # Create command with icon
  cmd = UI::Command.new("V003-FINAL-FIXED") {
    model = Sketchup.active_model
    selection = model.selection
    
    if selection.empty?
      UI.messagebox("Please select one or more faces to create V003-FINAL-FIXED layout.\n\nFIXED FEATURES:\n✅ Corner over-extension FIXED\n✅ Internal/External cavity logic\n✅ Real-time ghosting generation\n✅ Top/Bottom layout options\n✅ No confirmation popup", "V003-FINAL-FIXED")
      next
    end
    
    faces_data = V003_FINAL_FIXED.analyze_multi_face_selection(selection)
    
    if faces_data.empty?
      UI.messagebox("No valid faces found in selection.", "V003-FINAL-FIXED")
      next
    end
    
    unless V003_FINAL_FIXED.validate_faces_for_processing(faces_data)
      UI.messagebox("Selected faces are not suitable for processing.", "V003-FINAL-FIXED")
      next
    end
    
    multi_face_position = CladzFinalMultiFacePosition.new
    
    faces_data.each do |data|
      multi_face_position.add_face(data[:face], data[:matrix])
    end
    
    puts "[V003-FINAL-FIXED] Multi-face selection validated: #{multi_face_position.face_count} faces"
    
    result = V003_FINAL_FIXED.display_professional_dialog(multi_face_position, 0)
    
    if result == 0
      UI.messagebox("Layout creation failed. Check console for details.", "V003-FINAL-FIXED")
    end
  }
  
  # Set command properties
  cmd.menu_text = "V003-FINAL-FIXED"
  cmd.tooltip = "V003-FINAL-FIXED: Generate cladding layout with fixed corners"
  cmd.status_bar_text = "Generate V003-FINAL-FIXED cladding layout"
  cmd.small_icon = "TB_V003_FINAL_FIXED_16.png"
  cmd.large_icon = "TB_V003_FINAL_FIXED_24.png"
  
  # Add to toolbar
  toolbar = toolbar.add_item cmd
  toolbar.show
  
  # FIXED: Shortened menu name
  menu = UI.menu("Extensions")
  menu.add_item("V003-FINAL-FIXED") { cmd.invoke }
  
  puts "[V003-FINAL-FIXED] Toolbar and menu created"
  file_loaded(__FILE__)
end

puts "V003-FINAL-FIXED loaded successfully!"
puts "Features:"
puts "  ✅ FIXED: Corner over-extension (internal/external logic)"
puts "  ✅ FIXED: Cavity management for different corner types"
puts "  ✅ ADDED: Top and bottom layout starting points"
puts "  ✅ ADDED: Real-time ghosting generation for demos"
puts "  ✅ DISABLED: Confirmation popup for clean recording"
puts "  ✅ ADDED: Toolbar icon and shortened menu name"