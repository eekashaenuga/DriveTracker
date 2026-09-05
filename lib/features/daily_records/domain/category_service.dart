import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../data/category_repository.dart';
import 'record_category.dart';

typedef Clock = DateTime Function();

class CategoryService {
  CategoryService({
    required this.categoryRepository,
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final CategoryRepository categoryRepository;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<RecordCategory> createCustomCategory({
    required RecordCategoryType type,
    required String name,
    String? iconIdentifier,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const ValidationException(['Category name is required.']);
    }
    final existingCategory = await categoryRepository.findByTypeAndName(
      type,
      cleanName,
    );
    if (existingCategory != null) {
      throw ValidationException([
        'A category named "$cleanName" already exists.',
      ]);
    }

    final now = _clock().toUtc();
    final category = RecordCategory(
      id: _idGenerator.newId('cat'),
      type: type,
      name: cleanName,
      iconIdentifier: iconIdentifier?.trim(),
      sortOrder: await categoryRepository.nextSortOrder(type),
      systemCategory: false,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    await categoryRepository.insert(category);
    return category;
  }
}
