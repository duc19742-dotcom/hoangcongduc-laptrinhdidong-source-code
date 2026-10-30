import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LocationMap extends StatelessWidget {
  final double latitude, longitude, radius;
  final double? userLatitude, userLongitude, accuracy;
  const LocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.userLatitude,
    this.userLongitude,
    this.accuracy,
  });
  static bool valid(double? lat, double? lng) =>
      lat != null &&
      lng != null &&
      lat.isFinite &&
      lng.isFinite &&
      lat.abs() <= 90 &&
      lng.abs() <= 180;
  @override
  Widget build(BuildContext context) {
    if (!valid(latitude, longitude) || !radius.isFinite || radius <= 0) {
      return const Text('Nhập tọa độ và bán kính hợp lệ để xem bản đồ.');
    }
    final center = LatLng(latitude, longitude);
    final user = valid(userLatitude, userLongitude)
        ? LatLng(userLatitude!, userLongitude!)
        : null;
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 280,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: FlutterMap(
              key: ValueKey(
                '$latitude|$longitude|$userLatitude|$userLongitude|$radius',
              ),
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
                minZoom: 3,
                maxZoom: 19,
              ),
              children: [
                // flutter_map uses its built-in native disk cache and HTTP cache headers.
                // No offline downloads/prefetch; standard OSM tiles are for this small demo.
                TileLayer(
                  urlTemplate: const String.fromEnvironment(
                    'MAP_TILE_URL',
                    defaultValue:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  userAgentPackageName: 'vn.hoangcongduc.attendance',
                  panBuffer: 0,
                  maxNativeZoom: 19,
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: center,
                      radius: radius,
                      useRadiusInMeter: true,
                      color: color.withValues(alpha: .12),
                      borderColor: color,
                      borderStrokeWidth: 2,
                    ),
                    if (user != null &&
                        accuracy != null &&
                        accuracy!.isFinite &&
                        accuracy! > 0)
                      CircleMarker(
                        point: user,
                        radius: accuracy!,
                        useRadiusInMeter: true,
                        color: Colors.orange.withValues(alpha: .15),
                        borderColor: Colors.orange,
                        borderStrokeWidth: 1,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 44,
                      height: 44,
                      child: Icon(Icons.business, color: color, size: 32),
                    ),
                    if (user != null) constMarker(user),
                  ],
                ),
                const Align(
                  alignment: Alignment.bottomRight,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Text(
                        '© OpenStreetMap contributors\nopenstreetmap.org/copyright',
                        style: TextStyle(color: Colors.black87, fontSize: 10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tòa nhà: tâm địa điểm · Chấm xanh: vị trí của bạn. Bản đồ chỉ minh họa; kết quả do máy chủ kiểm tra. Nếu nền bản đồ chưa tải, vẫn có thể xem thông số GPS.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Marker constMarker(LatLng point) => Marker(
    point: point,
    width: 36,
    height: 36,
    child: const Icon(Icons.my_location, color: Colors.blue, size: 28),
  );
}
