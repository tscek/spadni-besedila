import 'package:path_provider/path_provider.dart';

import 'shramba.dart';
import 'shramba_datoteke.dart';

Shramba privzetaShramba() => ShrambaDatoteke(getApplicationSupportDirectory);
